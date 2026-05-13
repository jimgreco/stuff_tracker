import { Router, Request, Response } from 'express';
import { OAuth2Client } from 'google-auth-library';
import appleSignin from 'apple-signin-auth';
import { pool } from '../db/pool';
import { signToken } from '../lib/jwt';
import { requireAuth, AuthRequest } from '../middleware/auth';

const router = Router();
const googleClient = new OAuth2Client(process.env.GOOGLE_CLIENT_ID);

// ── Local dev sign-in (DEBUG/testing only) ────────────────────────────────────
router.post('/dev', async (req: Request, res: Response) => {
  if (process.env.NODE_ENV === 'production') {
    res.status(404).json({ error: 'Not found' });
    return;
  }

  const email = typeof req.body?.email === 'string' && req.body.email.trim()
    ? req.body.email.trim().toLowerCase()
    : 'dev@stufftracker.local';
  const name = typeof req.body?.name === 'string' && req.body.name.trim()
    ? req.body.name.trim()
    : 'Local Dev';

  const user = await upsertUser({ email, name });
  res.json({ token: signToken({ userId: user.id, email: user.email }), user });
});

// ── Google Sign-In (iOS sends the ID token directly) ──────────────────────────
router.post('/google', async (req: Request, res: Response) => {
  const { idToken } = req.body;
  if (!idToken) {
    res.status(400).json({ error: 'idToken required' });
    return;
  }

  try {
    const ticket = await googleClient.verifyIdToken({
      idToken,
      audience: process.env.GOOGLE_CLIENT_ID,
    });
    const payload = ticket.getPayload();
    if (!payload?.sub || !payload.email) {
      res.status(401).json({ error: 'Invalid Google token' });
      return;
    }

    const { sub: googleId, email, name = email, picture } = payload;
    const user = await upsertUser({ googleId, email, name, avatarUrl: picture });
    res.json({ token: signToken({ userId: user.id, email: user.email }), user });
  } catch (err: any) {
    console.error('Google sign-in verification failed:', err);
    res.status(401).json({ error: err.message ?? 'Google token verification failed' });
  }
});

// ── Apple Sign-In ──────────────────────────────────────────────────────────────
router.post('/apple', async (req: Request, res: Response) => {
  const { identityToken, fullName } = req.body;
  if (!identityToken) {
    res.status(400).json({ error: 'identityToken required' });
    return;
  }

  try {
    const applePayload = await appleSignin.verifyIdToken(identityToken, {
      audience: process.env.APPLE_BUNDLE_ID,
      ignoreExpiration: false,
    });

    const appleId = applePayload.sub;
    const email = applePayload.email ?? `${appleId}@privaterelay.appleid.com`;
    const name = fullName
      ? [fullName.givenName, fullName.familyName].filter(Boolean).join(' ')
      : email;

    const user = await upsertUser({ appleId, email, name });
    res.json({ token: signToken({ userId: user.id, email: user.email }), user });
  } catch (err: any) {
    console.error('Apple sign-in verification failed:', err);
    res.status(401).json({ error: err.message ?? 'Apple token verification failed' });
  }
});

// ── Current user ───────────────────────────────────────────────────────────────
router.get('/me', requireAuth, async (req: AuthRequest, res: Response) => {
  const { rows } = await pool.query(
    'SELECT id, email, name, avatar_url FROM users WHERE id = $1',
    [req.user!.userId]
  );
  if (!rows[0]) {
    res.status(404).json({ error: 'User not found' });
    return;
  }
  res.json(rows[0]);
});

// ── Helpers ────────────────────────────────────────────────────────────────────
async function upsertUser(params: {
  googleId?: string;
  appleId?: string;
  email: string;
  name: string;
  avatarUrl?: string;
}) {
  const { googleId, appleId, email, name, avatarUrl } = params;
  const { rows } = await pool.query(
    `INSERT INTO users (email, name, avatar_url, google_id, apple_id)
     VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (email) DO UPDATE
       SET name = EXCLUDED.name,
           avatar_url = COALESCE(EXCLUDED.avatar_url, users.avatar_url),
           google_id = COALESCE(EXCLUDED.google_id, users.google_id),
           apple_id = COALESCE(EXCLUDED.apple_id, users.apple_id),
           updated_at = NOW()
     RETURNING id, email, name, avatar_url`,
    [email, name, avatarUrl ?? null, googleId ?? null, appleId ?? null]
  );
  return rows[0];
}

export default router;
