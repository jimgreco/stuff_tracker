import { Router, Response } from 'express';
import { requireAuth, AuthRequest } from '../middleware/auth';
import { AppStoreTransactionSyncSchema } from '../lib/schemas';
import { accountPlan } from '../lib/entitlements';
import { applySignedAppStoreTransaction, appStoreProductIds } from '../lib/appStore';

const router = Router();
router.use(requireAuth);

router.get('/plan', async (req: AuthRequest, res: Response) => {
  res.json(await accountPlan(req.user!.userId));
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

export default router;
