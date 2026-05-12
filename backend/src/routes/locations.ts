import { Router, Response } from 'express';
import { z } from 'zod';
import { pool } from '../db/pool';
import { requireAuth, AuthRequest } from '../middleware/auth';
import { getHomeRole, canEdit } from '../lib/access';

const router = Router({ mergeParams: true });
router.use(requireAuth);

const LocationSchema = z.object({
  name: z.string().min(1).max(200),
  parent_id: z.string().uuid().nullable().optional(),
  type: z.enum(['room', 'container']),
  sort_order: z.number().int().optional(),
});

// ── Create location ────────────────────────────────────────────────────────────
router.post('/', async (req: AuthRequest, res: Response) => {
  const { homeId } = req.params;
  const role = await getHomeRole(homeId, req.user!.userId);
  if (!canEdit(role)) { res.status(403).json({ error: 'Edit access required' }); return; }

  const { name, parent_id, type, sort_order } = LocationSchema.parse(req.body);
  const { rows } = await pool.query(
    `INSERT INTO locations (home_id, parent_id, name, type, sort_order)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING id, home_id, parent_id, name, type, sort_order`,
    [homeId, parent_id ?? null, name, type, sort_order ?? 0]
  );
  res.status(201).json(rows[0]);
});

// ── Update location ────────────────────────────────────────────────────────────
router.patch('/:locationId', async (req: AuthRequest, res: Response) => {
  const { homeId, locationId } = req.params;
  const role = await getHomeRole(homeId, req.user!.userId);
  if (!canEdit(role)) { res.status(403).json({ error: 'Edit access required' }); return; }

  const updates = LocationSchema.partial().parse(req.body);
  const fields: string[] = [];
  const values: unknown[] = [];
  let i = 1;

  if (updates.name !== undefined) { fields.push(`name = $${i++}`); values.push(updates.name); }
  if (updates.parent_id !== undefined) { fields.push(`parent_id = $${i++}`); values.push(updates.parent_id); }
  if (updates.sort_order !== undefined) { fields.push(`sort_order = $${i++}`); values.push(updates.sort_order); }
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
