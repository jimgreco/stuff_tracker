import { Router, Response } from 'express';
import { pool } from '../db/pool';
import { requireAuth, AuthRequest } from '../middleware/auth';
import { getHomeRole, canEdit } from '../lib/access';
import { LocationSchema } from '../lib/schemas';
import { canCreateContainer, type QuotaDecision } from '../lib/entitlements';

const router = Router({ mergeParams: true });
router.use(requireAuth);

// ── Create location ────────────────────────────────────────────────────────────
router.post('/', async (req: AuthRequest, res: Response) => {
  const { homeId } = req.params;
  const role = await getHomeRole(homeId, req.user!.userId);
  if (!canEdit(role)) { res.status(403).json({ error: 'Edit access required' }); return; }

  const { name, parent_id, type, sort_order, icon } = LocationSchema.parse(req.body);
  if (type === 'container') {
    const quota = await canCreateContainer(homeId);
    if (quota) { sendQuota(res, quota); return; }
  }

  if (parent_id) {
    const parent = await pool.query(
      'SELECT id FROM locations WHERE id = $1 AND home_id = $2',
      [parent_id, homeId]
    );
    if (!parent.rows[0]) {
      res.status(400).json({ error: 'Parent location not found' });
      return;
    }
  }

  const { rows } = await pool.query(
    `INSERT INTO locations (home_id, parent_id, name, type, sort_order, icon)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING id, home_id, parent_id, name, type, sort_order, icon`,
    [homeId, parent_id ?? null, name, type, sort_order ?? 0, icon ?? null]
  );
  res.status(201).json(rows[0]);
});

// ── Update location ────────────────────────────────────────────────────────────
router.patch('/:locationId', async (req: AuthRequest, res: Response) => {
  const { homeId, locationId } = req.params;
  const role = await getHomeRole(homeId, req.user!.userId);
  if (!canEdit(role)) { res.status(403).json({ error: 'Edit access required' }); return; }

  const updates = LocationSchema.partial().parse(req.body);
  if (updates.parent_id) {
    if (updates.parent_id === locationId) {
      res.status(400).json({ error: 'Location cannot be its own parent' });
      return;
    }

    const parent = await pool.query(
      'SELECT id FROM locations WHERE id = $1 AND home_id = $2',
      [updates.parent_id, homeId]
    );
    if (!parent.rows[0]) {
      res.status(400).json({ error: 'Parent location not found' });
      return;
    }
  }

  const fields: string[] = [];
  const values: unknown[] = [];
  let i = 1;

  if (updates.name !== undefined) { fields.push(`name = $${i++}`); values.push(updates.name); }
  if (updates.parent_id !== undefined) { fields.push(`parent_id = $${i++}`); values.push(updates.parent_id); }
  if (updates.sort_order !== undefined) { fields.push(`sort_order = $${i++}`); values.push(updates.sort_order); }
  if (updates.icon !== undefined) { fields.push(`icon = $${i++}`); values.push(updates.icon); }
  if (!fields.length) { res.status(400).json({ error: 'Nothing to update' }); return; }

  fields.push(`updated_at = NOW()`);
  values.push(locationId, homeId);

  const { rows } = await pool.query(
    `UPDATE locations SET ${fields.join(', ')}
     WHERE id = $${i++} AND home_id = $${i} RETURNING *`,
    values
  );
  if (!rows[0]) { res.status(404).json({ error: 'Location not found' }); return; }
  res.json(rows[0]);
});

// ── Delete location ────────────────────────────────────────────────────────────
router.delete('/:locationId', async (req: AuthRequest, res: Response) => {
  const { homeId, locationId } = req.params;
  const role = await getHomeRole(homeId, req.user!.userId);
  if (!canEdit(role)) { res.status(403).json({ error: 'Edit access required' }); return; }

  await pool.query(
    'DELETE FROM locations WHERE id = $1 AND home_id = $2',
    [locationId, homeId]
  );
  res.status(204).send();
});

export default router;

function sendQuota(res: Response, quota: QuotaDecision): void {
  res.status(quota.status).json({ error: quota.error, code: quota.code, plan: quota.plan });
}
