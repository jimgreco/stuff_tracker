import { timingSafeEqual } from 'node:crypto';
import { Router, Request, Response } from 'express';
import { ManualEntitlementGrantSchema } from '../lib/schemas';
import { upsertUser } from '../lib/users';
import { pool } from '../db/pool';
import { accountPlan } from '../lib/entitlements';

const router = Router();

router.use((req: Request, res: Response, next) => {
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
