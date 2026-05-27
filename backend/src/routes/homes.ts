import { Router, Response } from 'express';
import { pool } from '../db/pool';
import { requireAuth, AuthRequest } from '../middleware/auth';
import { getHomeRole, canAdmin } from '../lib/access';
import { HomeSchema, InviteSchema, UpdateMemberRoleSchema } from '../lib/schemas';
import { signItemsAttachmentUrls } from '../lib/attachmentResponses';
import { canShareHome, type QuotaDecision } from '../lib/entitlements';

const router = Router();
router.use(requireAuth);

// ── List homes the user belongs to ────────────────────────────────────────────
router.get('/', async (req: AuthRequest, res: Response) => {
  const userId = req.user!.userId;
  const { rows } = await pool.query(
    `SELECT h.id, h.name, h.icon, h.owner_id, h.created_at,
            CASE WHEN h.owner_id = $1 THEN 'owner' ELSE hm.role END AS role
     FROM homes h
     LEFT JOIN home_members hm ON hm.home_id = h.id AND hm.user_id = $1
     WHERE h.owner_id = $1
        OR (
          hm.user_id = $1
          AND EXISTS (
            SELECT 1
            FROM user_entitlements ue
            WHERE ue.user_id = h.owner_id
              AND ue.status = 'active'
              AND ue.revoked_at IS NULL
              AND (ue.expires_at IS NULL OR ue.expires_at > NOW())
          )
        )
     ORDER BY h.name`,
    [userId]
  );
  res.json(rows);
});

// ── Create home ────────────────────────────────────────────────────────────────
router.post('/', async (req: AuthRequest, res: Response) => {
  const { name, icon } = HomeSchema.parse(req.body);
  const { rows } = await pool.query(
    `INSERT INTO homes (name, icon, owner_id) VALUES ($1, $2, $3)
     RETURNING id, name, icon, owner_id, created_at`,
    [name, icon ?? null, req.user!.userId]
  );
  res.status(201).json({ ...rows[0], role: 'owner' });
});

// ── Get single home (with full tree: rooms → containers → items) ───────────────
router.get('/:homeId', async (req: AuthRequest, res: Response) => {
  const { homeId } = req.params;
  const role = await getHomeRole(homeId, req.user!.userId);
  if (!role) { res.status(403).json({ error: 'Access denied' }); return; }

  const [homeRes, locRes, itemRes] = await Promise.all([
    pool.query('SELECT id, name, icon, owner_id FROM homes WHERE id = $1', [homeId]),
    pool.query(
      `SELECT id, home_id, parent_id, name, type, sort_order, icon FROM locations
       WHERE home_id = $1 ORDER BY sort_order, name`,
      [homeId]
    ),
    pool.query(
      `SELECT id, home_id, location_id, name, icon, notes, quantity, properties, photo_urls,
              documents, purchase_date, serial_number, model_number, warranty_expires_date,
              estimated_value_cents, created_by
       FROM items WHERE home_id = $1 ORDER BY name`,
      [homeId]
    ),
  ]);

  if (!homeRes.rows[0]) { res.status(404).json({ error: 'Home not found' }); return; }
  res.json({
    ...homeRes.rows[0],
    role,
    locations: locRes.rows,
    items: await signItemsAttachmentUrls(itemRes.rows),
  });
});

// ── Update home ────────────────────────────────────────────────────────────────
router.patch('/:homeId', async (req: AuthRequest, res: Response) => {
  const { homeId } = req.params;
  const role = await getHomeRole(homeId, req.user!.userId);
  if (!canAdmin(role)) { res.status(403).json({ error: 'Admin access required' }); return; }

  const { name, icon } = HomeSchema.parse(req.body);
  const { rows } = await pool.query(
    'UPDATE homes SET name = $1, icon = $2, updated_at = NOW() WHERE id = $3 RETURNING id, name, icon, owner_id',
    [name, icon ?? null, homeId]
  );
  res.json({ ...rows[0], role });
});

// ── Delete home ────────────────────────────────────────────────────────────────
router.delete('/:homeId', async (req: AuthRequest, res: Response) => {
  const { homeId } = req.params;
  const { rows } = await pool.query('SELECT owner_id FROM homes WHERE id = $1', [homeId]);
  if (!rows[0] || rows[0].owner_id !== req.user!.userId) {
    res.status(403).json({ error: 'Only the owner can delete a home' }); return;
  }
  await pool.query('DELETE FROM homes WHERE id = $1', [homeId]);
  res.status(204).send();
});

// ── Members ────────────────────────────────────────────────────────────────────
router.get('/:homeId/members', async (req: AuthRequest, res: Response) => {
  const { homeId } = req.params;
  const role = await getHomeRole(homeId, req.user!.userId);
  if (!role) { res.status(403).json({ error: 'Access denied' }); return; }

  const { rows } = await pool.query(
    `SELECT u.id, u.email, u.name, u.avatar_url, hm.role
     FROM home_members hm JOIN users u ON u.id = hm.user_id
     WHERE hm.home_id = $1`,
    [homeId]
  );
  res.json(rows);
});

router.post('/:homeId/members', async (req: AuthRequest, res: Response) => {
  const { homeId } = req.params;
  const role = await getHomeRole(homeId, req.user!.userId);
  if (!canAdmin(role)) { res.status(403).json({ error: 'Admin access required' }); return; }
  const quota = await canShareHome(homeId);
  if (quota) { sendQuota(res, quota); return; }

  const { email, role: newRole } = InviteSchema.parse(req.body);
  const userRes = await pool.query(
    `WITH invitee AS (
       INSERT INTO users (email, name)
       VALUES ($1, $1)
       ON CONFLICT (email) DO NOTHING
       RETURNING id
     )
     SELECT id FROM invitee
     UNION ALL
     SELECT id FROM users WHERE email = $1
     LIMIT 1`,
    [email]
  );

  const inviteeId = userRes.rows[0].id;
  await pool.query(
    `INSERT INTO home_members (home_id, user_id, role, invited_by)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (home_id, user_id) DO UPDATE SET role = EXCLUDED.role`,
    [homeId, inviteeId, newRole, req.user!.userId]
  );
  res.status(201).json({ message: 'Member added', role: newRole });
});

router.patch('/:homeId/members/:userId', async (req: AuthRequest, res: Response) => {
  const { homeId, userId } = req.params;
  const role = await getHomeRole(homeId, req.user!.userId);
  if (!canAdmin(role)) { res.status(403).json({ error: 'Admin access required' }); return; }
  const quota = await canShareHome(homeId);
  if (quota) { sendQuota(res, quota); return; }

  const { role: newRole } = UpdateMemberRoleSchema.parse(req.body);
  await pool.query(
    'UPDATE home_members SET role = $1 WHERE home_id = $2 AND user_id = $3',
    [newRole, homeId, userId]
  );
  res.json({ role: newRole });
});

router.delete('/:homeId/members/:userId', async (req: AuthRequest, res: Response) => {
  const { homeId, userId } = req.params;
  const role = await getHomeRole(homeId, req.user!.userId);
  // Admins can remove others; anyone can remove themselves
  if (!canAdmin(role) && userId !== req.user!.userId) {
    res.status(403).json({ error: 'Admin access required' }); return;
  }
  await pool.query(
    'DELETE FROM home_members WHERE home_id = $1 AND user_id = $2',
    [homeId, userId]
  );
  res.status(204).send();
});

export default router;

function sendQuota(res: Response, quota: QuotaDecision): void {
  res.status(quota.status).json({ error: quota.error, code: quota.code, plan: quota.plan });
}
