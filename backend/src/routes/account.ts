import { Router, Response } from 'express';
import { requireAuth, AuthRequest } from '../middleware/auth';
import { AppStoreTransactionSyncSchema } from '../lib/schemas';
import { accountPlan } from '../lib/entitlements';
import { applySignedAppStoreTransaction, appStoreProductIds } from '../lib/appStore';
import { isAdminEmail } from '../lib/adminUsers';
import { pool } from '../db/pool';
import { deleteHomeAttachments } from '../lib/s3';

const router = Router();
router.use(requireAuth);

router.get('/sync-capabilities', (_req: AuthRequest, res: Response) => {
  res.set('Cache-Control', 'no-store').json({ client_create_receipts: 1 });
});

router.get('/plan', async (req: AuthRequest, res: Response) => {
  const isAdmin = isAdminEmail(req.user!.email);
  res.json({
    ...await accountPlan(req.user!.userId),
    isAdmin,
    is_admin: isAdmin,
  });
});

router.get('/subscription-products', (_req: AuthRequest, res: Response) => {
  res.json({ product_ids: appStoreProductIds() });
});

router.post('/app-store/transactions', async (req: AuthRequest, res: Response) => {
  const { signed_transaction_info } = AppStoreTransactionSyncSchema.parse(req.body);
  const result = await applySignedAppStoreTransaction(signed_transaction_info, req.user!.userId);

  if (!result.applied) {
    const status = result.ignoredReason === 'transaction_belongs_to_different_user' ? 409 : 400;
    res.status(status).json({ error: 'App Store transaction was not applied', reason: result.ignoredReason });
    return;
  }

  res.json({
    result,
    plan: await accountPlan(req.user!.userId),
  });
});

router.delete('/', async (req: AuthRequest, res: Response) => {
  if (req.body?.confirmation !== 'DELETE') {
    res.status(400).json({ error: 'Account deletion confirmation required' });
    return;
  }

  const userId = req.user!.userId;
  const client = await pool.connect();
  let ownedHomeIds: string[] = [];
  try {
    await client.query('BEGIN');
    const user = await client.query('SELECT id FROM users WHERE id = $1 FOR UPDATE', [userId]);
    if (!user.rows.length) {
      await client.query('ROLLBACK');
      res.status(404).json({ error: 'Account not found' });
      return;
    }

    const homes = await client.query<{ id: string }>('SELECT id FROM homes WHERE owner_id = $1', [userId]);
    ownedHomeIds = homes.rows.map(({ id }) => id);
    await client.query('DELETE FROM app_store_transactions WHERE user_id = $1', [userId]);
    await client.query('DELETE FROM users WHERE id = $1', [userId]);

    // Activity history has no foreign keys, so remove owned-home history and
    // anonymize the former member's actions in homes that remain shared.
    await client.query('DELETE FROM home_activity_events WHERE home_id = ANY($1::uuid[])', [ownedHomeIds]);
    await client.query(
      `UPDATE home_activity_events
       SET actor_id = NULL, actor_name = NULL, actor_email = NULL, mutation_id = NULL
       WHERE actor_id = $1`,
      [userId]
    );
    await client.query(
      `UPDATE home_activity_events
       SET entity_id = NULL, entity_name = 'Former member', summary = 'Member changed'
       WHERE entity_type = 'member' AND entity_id = $1`,
      [userId]
    );
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }

  try {
    await deleteHomeAttachments(ownedHomeIds);
  } catch (error) {
    // The scheduled orphan cleanup can remove these objects after the DB deletion.
    console.error('Account attachments could not be removed immediately:', error);
  }
  res.status(204).send();
});

export default router;
