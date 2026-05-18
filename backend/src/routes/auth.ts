import { Router, Request, Response } from 'express';
import { OAuth2Client } from 'google-auth-library';
import appleSignin from 'apple-signin-auth';
import { pool } from '../db/pool';
import { readAppleFullName, readAuthString } from '../lib/authPayload';
import { signToken } from '../lib/jwt';
import { requireAuth, AuthRequest } from '../middleware/auth';
import { upsertUser, UserIdentityConflictError } from '../lib/users';

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
  const idToken = readAuthString(req.body, 'idToken', 'id_token');
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
    if (err instanceof UserIdentityConflictError) {
      res.status(409).json({ error: err.message });
      return;
    }
    console.error('Google sign-in verification failed:', err);
    res.status(401).json({ error: err.message ?? 'Google token verification failed' });
  }
});

// ── Apple Sign-In ──────────────────────────────────────────────────────────────
router.post('/apple', async (req: Request, res: Response) => {
  const identityToken = readAuthString(req.body, 'identityToken', 'identity_token');
  const fullName = readAppleFullName(req.body);
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
    const emailIsFallback = !applePayload.email;
    const email = applePayload.email ?? `${appleId}@privaterelay.appleid.com`;
    const providedName = fullName
      ? [fullName.givenName, fullName.familyName].filter(Boolean).join(' ')
      : '';
    const name = providedName || email;

    const user = await upsertUser({ appleId, email, name, emailIsFallback });
    res.json({ token: signToken({ userId: user.id, email: user.email }), user });
  } catch (err: any) {
    if (err instanceof UserIdentityConflictError) {
      res.status(409).json({ error: err.message });
      return;
    }
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

export default router;
