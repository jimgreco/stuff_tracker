import { Router, Request, Response } from 'express';
import { OAuth2Client } from 'google-auth-library';
import appleSignin from 'apple-signin-auth';
import { pool } from '../db/pool';
import { readAppleFullName, readAuthString } from '../lib/authPayload';
import { signToken } from '../lib/jwt';
import { requireAuth, AuthRequest } from '../middleware/auth';
import { upsertUser, UserIdentityConflictError } from '../lib/users';
import {
  createAuthSession,
  listAuthSessions,
  refreshAuthSession,
  revokeAllAuthSessions,
  revokeAuthSession,
} from '../lib/sessions';

const router = Router();
const googleClient = new OAuth2Client(process.env.GOOGLE_CLIENT_ID);

function unique(values: Array<string | undefined>): string[] {
  return Array.from(new Set(values.map((value) => value?.trim()).filter((value): value is string => Boolean(value))));
}

function googleAudiences(): string[] {
  return unique([process.env.GOOGLE_CLIENT_ID, process.env.GOOGLE_WEB_CLIENT_ID]);
}

function webGoogleClientId(): string | undefined {
  return process.env.GOOGLE_WEB_CLIENT_ID?.trim();
}

function appleAudiences(): string[] {
  return unique([process.env.APPLE_BUNDLE_ID, process.env.APPLE_WEB_CLIENT_ID]);
}

function webAppleClientId(): string | undefined {
  return process.env.APPLE_WEB_CLIENT_ID?.trim();
}

async function issueAuthResponse(req: Request, user: { id: string; email: string }) {
  const session = await createAuthSession(user.id, req);
  return {
    token: signToken({
      userId: user.id,
      email: user.email,
      sessionId: session.sessionId,
      jti: session.tokenId,
    }),
    refreshToken: session.refreshToken,
    user,
  };
}

function issueSessionToken(session: { sessionId: string; tokenId: string }, user: { id: string; email: string }) {
  return signToken({
    userId: user.id,
    email: user.email,
    sessionId: session.sessionId,
    jti: session.tokenId,
  });
}

async function verifyAppleIdentityToken(identityToken: string) {
  let lastError: unknown;
  const audiences = appleAudiences();
  if (audiences.length === 0) {
    throw new Error('Apple Sign-In is not configured');
  }

  for (const audience of audiences) {
    try {
      return await appleSignin.verifyIdToken(identityToken, {
        audience,
        ignoreExpiration: false,
      });
    } catch (err) {
      lastError = err;
    }
  }
  throw lastError ?? new Error('Apple Sign-In audience is not configured');
}

router.get('/config', (_req: Request, res: Response) => {
  res.json({
    google_client_id: webGoogleClientId() ?? null,
    apple_client_id: webAppleClientId() ?? null,
  });
});

router.post('/refresh', async (req: Request, res: Response) => {
  const refreshToken = readAuthString(req.body, 'refreshToken', 'refresh_token');
  if (!refreshToken) {
    res.status(400).json({ error: 'refreshToken required' });
    return;
  }

  const session = await refreshAuthSession(refreshToken, req);
  if (!session) {
    res.status(401).json({ error: 'Invalid or expired refresh token' });
    return;
  }

  res.json({
    token: issueSessionToken(session, session.user),
    refreshToken: session.refreshToken,
    user: session.user,
  });
});

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
  res.json(await issueAuthResponse(req, user));
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
      audience: googleAudiences(),
    });
    const payload = ticket.getPayload();
    if (!payload?.sub || !payload.email) {
      res.status(401).json({ error: 'Invalid Google token' });
      return;
    }

    const { sub: googleId, email, name = email, picture } = payload;
    const user = await upsertUser({ googleId, email, name, avatarUrl: picture });
    res.json(await issueAuthResponse(req, user));
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
  if (appleAudiences().length === 0) {
    res.status(503).json({ error: 'Apple Sign-In is not configured' });
    return;
  }

  try {
    const applePayload = await verifyAppleIdentityToken(identityToken);

    const appleId = applePayload.sub;
    const emailIsFallback = !applePayload.email;
    const email = applePayload.email ?? `${appleId}@privaterelay.appleid.com`;
    const providedName = fullName
      ? [fullName.givenName, fullName.familyName].filter(Boolean).join(' ')
      : '';
    const name = providedName || email;

    const user = await upsertUser({ appleId, email, name, emailIsFallback });
    res.json(await issueAuthResponse(req, user));
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

router.get('/sessions', requireAuth, async (req: AuthRequest, res: Response) => {
  res.json(await listAuthSessions(req.user!.userId, req.user!.sessionId));
});

router.delete('/sessions/:sessionId', requireAuth, async (req: AuthRequest, res: Response) => {
  const revoked = await revokeAuthSession(req.user!.userId, req.params.sessionId);
  if (!revoked) {
    res.status(404).json({ error: 'Session not found' });
    return;
  }

  res.status(204).send();
});

router.post('/logout-all', requireAuth, async (req: AuthRequest, res: Response) => {
  await pool.query(
    'UPDATE users SET tokens_revoked_before = NOW(), updated_at = NOW() WHERE id = $1',
    [req.user!.userId]
  );
  await revokeAllAuthSessions(req.user!.userId);
  res.status(204).send();
});

export default router;
