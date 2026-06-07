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

  const { name, parent_id, type, sort_order, icon, is_flagged } = LocationSchema.parse(req.body);
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
    `INSERT INTO locations (home_id, parent_id, name, type, sort_order, icon, is_flagged)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     RETURNING id, home_id, parent_id, name, type, sort_order, icon, is_flagged`,
    [homeId, parent_id ?? null, name, type, sort_order ?? 0, icon ?? null, is_flagged ?? false]
  );
  res.status(201).json(rows[0]);
});

// ── Update location ────────────────────────────────────────────────────────────
router.patch('/:locationId', async (req: AuthRequest, res: Response) => {
  const { homeId, locationId } = req.params;
  const updates = LocationSchema.partial().parse(req.body);
  const current = await pool.query(
    'SELECT id, home_id FROM locations WHERE id = $1',
    [locationId]
  );
  if (!current.rows[0]) { res.status(404).json({ error: 'Location not found' }); return; }

  const currentHomeId = current.rows[0].home_id as string;
  if (currentHomeId !== homeId && updates.home_id !== homeId) {
    res.status(404).json({ error: 'Location not found' });
    return;
  }

  const targetHomeId = updates.home_id ?? currentHomeId;
  const currentRole = await getHomeRole(currentHomeId, req.user!.userId);
  const targetRole = targetHomeId === currentHomeId
    ? currentRole
    : await getHomeRole(targetHomeId, req.user!.userId);
  if (!canEdit(currentRole) || !canEdit(targetRole)) { res.status(403).json({ error: 'Edit access required' }); return; }

  if (updates.home_id !== undefined && updates.home_id !== currentHomeId && updates.parent_id === undefined) {
    updates.parent_id = null;
  }

  if (updates.parent_id) {
    if (updates.parent_id === locationId) {
      res.status(400).json({ error: 'Location cannot be its own parent' });
      return;
    }

    const parent = await pool.query(
      'SELECT id FROM locations WHERE id = $1 AND home_id = $2',
      [updates.parent_id, targetHomeId]
    );
    if (!parent.rows[0]) {
      res.status(400).json({ error: 'Parent location not found' });
      return;
    }

    const descendant = await pool.query(
      `WITH RECURSIVE subtree AS (
         SELECT id FROM locations WHERE id = $1
         UNION ALL
         SELECT l.id FROM locations l
         JOIN subtree s ON l.parent_id = s.id
       )
       SELECT id FROM subtree WHERE id = $2`,
      [locationId, updates.parent_id]
    );
    if (descendant.rows[0]) {
      res.status(400).json({ error: 'Location cannot move inside itself' });
      return;
    }
  }

  const fields: string[] = [];
  const values: unknown[] = [];
  let i = 1;

  if (updates.home_id !== undefined) { fields.push(`home_id = $${i++}`); values.push(updates.home_id); }
  if (updates.name !== undefined) { fields.push(`name = $${i++}`); values.push(updates.name); }
  if (updates.parent_id !== undefined) { fields.push(`parent_id = $${i++}`); values.push(updates.parent_id); }
  if (updates.sort_order !== undefined) { fields.push(`sort_order = $${i++}`); values.push(updates.sort_order); }
  if (updates.icon !== undefined) { fields.push(`icon = $${i++}`); values.push(updates.icon); }
  if (updates.is_flagged !== undefined) { fields.push(`is_flagged = $${i++}`); values.push(updates.is_flagged); }
  if (!fields.length) { res.status(400).json({ error: 'Nothing to update' }); return; }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    fields.push(`updated_at = NOW()`);
    values.push(locationId);

    const { rows } = await client.query(
      `UPDATE locations SET ${fields.join(', ')}
       WHERE id = $${i++} RETURNING *`,
      values
    );
    if (!rows[0]) {
      await client.query('ROLLBACK');
      res.status(404).json({ error: 'Location not found' });
      return;
    }

    if (updates.home_id !== undefined && updates.home_id !== currentHomeId) {
      await client.query(
        `WITH RECURSIVE subtree AS (
           SELECT id FROM locations WHERE id = $1
           UNION ALL
           SELECT l.id FROM locations l
           JOIN subtree s ON l.parent_id = s.id
         )
         UPDATE locations
         SET home_id = $2, updated_at = NOW()
         WHERE id IN (SELECT id FROM subtree)`,
        [locationId, updates.home_id]
      );
      await client.query(
        `WITH RECURSIVE subtree AS (
           SELECT id FROM locations WHERE id = $1
           UNION ALL
           SELECT l.id FROM locations l
           JOIN subtree s ON l.parent_id = s.id
         )
         UPDATE items
         SET home_id = $2, updated_at = NOW()
         WHERE location_id IN (SELECT id FROM subtree)`,
        [locationId, updates.home_id]
      );
    }

    await client.query('COMMIT');
    const moved = await pool.query('SELECT * FROM locations WHERE id = $1', [locationId]);
    res.json(moved.rows[0]);
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
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
