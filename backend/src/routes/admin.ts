import { timingSafeEqual } from 'node:crypto';
import { Router, Request, Response, NextFunction } from 'express';
import { ManualEntitlementGrantSchema } from '../lib/schemas';
import { upsertUser } from '../lib/users';
import { pool } from '../db/pool';
import { accountPlan } from '../lib/entitlements';
import { requireAuth, AuthRequest } from '../middleware/auth';
import { isAdminEmail } from '../lib/adminUsers';

const router = Router();
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type AdminTargetUser = {
  id: string;
  email: string;
  name: string | null;
};

type AdminEntitlementRow = {
  id: string;
  user_id: string;
  source: string;
  status: string;
  expires_at: Date | null;
};

router.get('/overview', requireAuth, requireSignedInAdmin, async (req: AuthRequest, res: Response) => {
  const [totalsResult, usersResult] = await Promise.all([
    pool.query(`
      SELECT
        (SELECT COUNT(*) FROM users) AS users,
        (SELECT COUNT(*) FROM homes) AS homes,
        (SELECT COUNT(*) FROM locations) AS locations,
        (SELECT COUNT(*) FROM items) AS items,
        (SELECT COUNT(*) FROM user_entitlements WHERE status = 'active' AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at > NOW())) AS active_entitlements,
        (SELECT COUNT(*) FROM auth_sessions WHERE revoked_at IS NULL) AS active_sessions
    `),
    pool.query(`
      SELECT
        u.id,
        u.email,
        u.name,
        u.created_at,
        u.updated_at,
        COUNT(DISTINCT h.id) AS home_count,
        COUNT(DISTINCT hm.home_id) AS shared_home_count,
        COUNT(DISTINCT i.id) AS item_count,
        COUNT(DISTINCT s.id) FILTER (WHERE s.revoked_at IS NULL) AS active_session_count,
        MAX(s.last_seen_at) AS last_seen_at,
        entitlement.source AS active_entitlement_source,
        entitlement.expires_at AS active_entitlement_expires_at
      FROM users u
      LEFT JOIN homes h ON h.owner_id = u.id
      LEFT JOIN home_members hm ON hm.user_id = u.id
      LEFT JOIN items i ON i.created_by = u.id
      LEFT JOIN auth_sessions s ON s.user_id = u.id
      LEFT JOIN LATERAL (
        SELECT source, expires_at
        FROM user_entitlements
        WHERE user_id = u.id
          AND status = 'active'
          AND revoked_at IS NULL
          AND (expires_at IS NULL OR expires_at > NOW())
        ORDER BY expires_at NULLS LAST, created_at DESC
        LIMIT 1
      ) entitlement ON TRUE
      GROUP BY u.id, entitlement.source, entitlement.expires_at
      ORDER BY u.created_at DESC
      LIMIT 100
    `),
  ]);

  const totals = totalsResult.rows[0] ?? {};
  res.json({
    generated_at: new Date().toISOString(),
    current_user: {
      id: req.user!.userId,
      email: req.user!.email,
    },
    totals: {
      users: numeric(totals.users),
      homes: numeric(totals.homes),
      locations: numeric(totals.locations),
      items: numeric(totals.items),
      active_entitlements: numeric(totals.active_entitlements),
      active_sessions: numeric(totals.active_sessions),
    },
    users: usersResult.rows.map((user) => ({
      id: user.id,
      email: user.email,
      name: user.name,
      created_at: user.created_at,
      updated_at: user.updated_at,
      home_count: numeric(user.home_count),
      shared_home_count: numeric(user.shared_home_count),
      item_count: numeric(user.item_count),
      active_session_count: numeric(user.active_session_count),
      last_seen_at: user.last_seen_at,
      active_entitlement_source: user.active_entitlement_source,
      active_entitlement_expires_at: user.active_entitlement_expires_at,
    })),
  });
});

router.post('/users/:userId/manual-entitlement', requireAuth, requireSignedInAdmin, async (req: AuthRequest, res: Response) => {
  const user = await findAdminTargetUser(req.params.userId, res);
  if (!user) {
    return;
  }

  await revokeManualEntitlements(user.id, req.user!, 'replaced_by_manual_paid');
  const { rows } = await pool.query<AdminEntitlementRow>(
    `INSERT INTO user_entitlements (user_id, source, status, expires_at, metadata)
     VALUES (
       $1,
       'manual',
       'active',
       NULL,
       jsonb_build_object('grantedBy', 'admin_page', 'adminUserId', $2::text, 'adminEmail', $3::text)
     )
     RETURNING id, user_id, source, status, expires_at`,
    [user.id, req.user!.userId, req.user!.email]
  );

  res.status(201).json({
    entitlement: rows[0],
    user,
    plan: await accountPlan(user.id),
  });
});

router.delete('/users/:userId/manual-entitlement', requireAuth, requireSignedInAdmin, async (req: AuthRequest, res: Response) => {
  const user = await findAdminTargetUser(req.params.userId, res);
  if (!user) {
    return;
  }

  const revokedCount = await revokeManualEntitlements(user.id, req.user!, 'set_back_to_free');

  res.json({
    revoked_count: revokedCount,
    user,
    plan: await accountPlan(user.id),
  });
});

router.use((req: Request, res: Response, next: NextFunction) => {
  const expected = process.env.ADMIN_API_TOKEN?.trim();
  if (!expected) {
    res.status(404).json({ error: 'Not found' });
    return;
  }

  const provided = readAdminToken(req);
  if (!provided || !constantTimeEqual(provided, expected)) {
    res.status(401).json({ error: 'Admin token required' });
    return;
  }

  next();
});

router.post('/entitlements', async (req: Request, res: Response) => {
  const { email, source, expires_at } = ManualEntitlementGrantSchema.parse(req.body);
  const expiresAt = expires_at ? new Date(expires_at) : null;
  if (expiresAt && expiresAt <= new Date()) {
    res.status(400).json({ error: 'expires_at must be in the future' });
    return;
  }

  const user = await upsertUser({ email, name: email });
  const { rows } = await pool.query(
    `INSERT INTO user_entitlements (user_id, source, status, expires_at, metadata)
     VALUES ($1, $2, 'active', $3, $4)
     RETURNING id, user_id, source, status, expires_at`,
    [user.id, source, expiresAt, JSON.stringify({ grantedBy: 'admin_api' })]
  );

  res.status(201).json({
    entitlement: rows[0],
    user,
    plan: await accountPlan(user.id),
  });
});

export default router;

function requireSignedInAdmin(req: AuthRequest, res: Response, next: NextFunction) {
  if (!isAdminEmail(req.user?.email)) {
    res.status(403).json({ error: 'Admin access required' });
    return;
  }

  next();
}

function numeric(value: unknown): number {
  const number = Number(value ?? 0);
  return Number.isFinite(number) ? number : 0;
}

async function findAdminTargetUser(userId: string, res: Response): Promise<AdminTargetUser | undefined> {
  if (!UUID_PATTERN.test(userId)) {
    res.status(400).json({ error: 'Invalid user id' });
    return undefined;
  }

  const { rows } = await pool.query<AdminTargetUser>(
    'SELECT id, email, name FROM users WHERE id = $1 LIMIT 1',
    [userId]
  );
  const user = rows[0];
  if (!user) {
    res.status(404).json({ error: 'User not found' });
    return undefined;
  }

  return user;
}

async function revokeManualEntitlements(
  userId: string,
  adminUser: NonNullable<AuthRequest['user']>,
  reason: string
): Promise<number> {
  const result = await pool.query(
    `UPDATE user_entitlements
     SET status = 'revoked',
         revoked_at = COALESCE(revoked_at, NOW()),
         updated_at = NOW(),
         metadata = metadata || jsonb_build_object(
           'revokedBy', 'admin_page',
           'revokedByUserId', $2::text,
           'revokedByEmail', $3::text,
           'revokedReason', $4::text
         )
     WHERE user_id = $1
       AND source IN ('manual', 'promo', 'admin')
       AND status = 'active'
       AND revoked_at IS NULL
       AND (expires_at IS NULL OR expires_at > NOW())`,
    [userId, adminUser.userId, adminUser.email, reason]
  );

  return result.rowCount ?? 0;
}

function readAdminToken(req: Request): string | undefined {
  const headerToken = req.header('x-admin-token')?.trim();
  if (headerToken) {
    return headerToken;
  }

  const auth = req.header('authorization') ?? '';
  const match = auth.match(/^Bearer\s+(.+)$/i);
  return match?.[1]?.trim();
}

function constantTimeEqual(a: string, b: string): boolean {
  const left = Buffer.from(a);
  const right = Buffer.from(b);
  return left.length === right.length && timingSafeEqual(left, right);
}
