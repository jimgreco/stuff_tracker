import { Router, Response } from 'express';
import { z } from 'zod';
import { pool } from '../db/pool';
import { requireAuth, AuthRequest } from '../middleware/auth';
import { getHomeRole, canEdit } from '../lib/access';

const router = Router({ mergeParams: true });
router.use(requireAuth);

const ItemSchema = z.object({
  name: z.string().min(1).max(200),
  location_id: z.string().uuid().nullable().optional(),
  notes: z.string().max(2000).nullable().optional(),
  quantity: z.number().int().min(1).optional(),
  tags: z.array(z.string()).optional(),
  photo_url: z.string().url().nullable().optional(),
  purchase_date: z.string().nullable().optional(), // ISO date string
});

// ── Create item ────────────────────────────────────────────────────────────────
router.post('/', async (req: AuthRequest, res: Response) => {
  const { homeId } = req.params;
  const role = await getHomeRole(homeId, req.user!.userId);
  if (!canEdit(role)) { res.status(403).json({ error: 'Edit access required' }); return; }

  const { name, location_id, notes, quantity, tags, photo_url, purchase_date } = ItemSchema.parse(req.body);
  const { rows } = await pool.query(
    `INSERT INTO items (home_id, location_id, name, notes, quantity, tags, photo_url, purchase_date, created_by)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
     RETURNING *`,
    [
      homeId,
      location_id ?? null,
      name,
      notes ?? null,
      quantity ?? 1,
      tags ?? [],
      photo_url ?? null,
      purchase_date ?? null,
      req.user!.userId,
    ]
  );
  res.status(201).json(rows[0]);
});

// ── Update item ────────────────────────────────────────────────────────────────
router.patch('/:itemId', async (req: AuthRequest, res: Response) => {
  const { homeId, itemId } = req.params;
  const role = await getHomeRole(homeId, req.user!.userId);
  if (!canEdit(role)) { res.status(403).json({ error: 'Edit access required' }); return; }

  const updates = ItemSchema.partial().parse(req.body);
  const fields: string[] = [];
  const values: unknown[] = [];
  let i = 1;

  const allowed = ['name', 'location_id', 'notes', 'quantity', 'tags', 'photo_url', 'purchase_date'] as const;
  for (const key of allowed) {
    if (key in updates) {
      fields.push(`${key} = $${i++}`);
      values.push((updates as Record<string, unknown>)[key] ?? null);
    }
  }
  if (!fields.length) { res.status(400).json({ error: 'Nothing to update' }); return; }

  fields.push(`updated_at = NOW()`);
  values.push(itemId, homeId);

  const { rows } = await pool.query(
    `UPDATE items SET ${fields.join(', ')}
     WHERE id = $${i++} AND home_id = $${i} RETURNING *`,
    values
  );
  if (!rows[0]) { res.status(404).json({ error: 'Item not found' }); return; }
  res.json(rows[0]);
});

// ── Delete item ────────────────────────────────────────────────────────────────
router.delete('/:itemId', async (req: AuthRequest, res: Response) => {
  const { homeId, itemId } = req.params;
  const role = await getHomeRole(homeId, req.user!.userId);
  if (!canEdit(role)) { res.status(403).json({ error: 'Edit access required' }); return; }

  await pool.query('DELETE FROM items WHERE id = $1 AND home_id = $2', [itemId, homeId]);
  res.status(204).send();
});

// ── Search items within a home ─────────────────────────────────────────────────
router.get('/search', async (req: AuthRequest, res: Response) => {
  const { homeId } = req.params;
  const role = await getHomeRole(homeId, req.user!.userId);
  if (!role) { res.status(403).json({ error: 'Access denied' }); return; }

  const q = String(req.query.q ?? '').trim();
  if (!q) { res.json([]); return; }

  const { rows } = await pool.query(
    `SELECT i.*, l.name AS location_name, l.parent_id AS location_parent_id
     FROM items i
     LEFT JOIN locations l ON l.id = i.location_id
     WHERE i.home_id = $1
       AND to_tsvector('english', i.name || ' ' || COALESCE(i.notes, '')) @@ plainto_tsquery('english', $2)
     ORDER BY ts_rank(to_tsvector('english', i.name || ' ' || COALESCE(i.notes, '')), plainto_tsquery('english', $2)) DESC
     LIMIT 50`,
    [homeId, q]
  );
  res.json(rows);
});

export default router;
