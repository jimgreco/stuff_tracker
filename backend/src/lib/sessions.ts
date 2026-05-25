import { Request } from 'express';
import { createHash, randomBytes } from 'node:crypto';
import { pool } from '../db/pool';
import { getIntegerEnv } from './env';

const MAX_USER_AGENT_LENGTH = 500;
const REFRESH_TOKEN_BYTES = 32;
const DEFAULT_REFRESH_TOKEN_DAYS = 90;

export interface CreatedAuthSession {
  sessionId: string;
  tokenId: string;
  refreshToken: string;
}

export interface RefreshedAuthSession {
  sessionId: string;
  tokenId: string;
  refreshToken: string;
  user: {
    id: string;
    email: string;
    name: string;
    avatar_url: string | null;
  };
}

export interface AuthSessionSummary {
  id: string;
  created_at: string;
  last_seen_at: string;
  user_agent: string | null;
  ip_address: string | null;
  current_session: boolean;
}

export async function createAuthSession(userId: string, req: Request): Promise<CreatedAuthSession> {
  const refreshToken = generateRefreshToken();
  const { rows } = await pool.query(
    `INSERT INTO auth_sessions (user_id, user_agent, ip_address, refresh_token_hash, refresh_token_expires_at)
     VALUES ($1, $2, $3, $4, NOW() + ($5::text || ' days')::interval)
     RETURNING id, token_id`,
    [
      userId,
      cleanUserAgent(req.get('user-agent')),
      requestIp(req),
      hashRefreshToken(refreshToken),
      refreshTokenDays(),
    ]
  );

  return {
    sessionId: rows[0].id,
    tokenId: rows[0].token_id,
    refreshToken,
  };
}

export async function refreshAuthSession(
  refreshToken: string,
  req: Request
): Promise<RefreshedAuthSession | undefined> {
  const nextRefreshToken = generateRefreshToken();
  const { rows } = await pool.query(
    `UPDATE auth_sessions AS s
     SET token_id = gen_random_uuid(),
         refresh_token_hash = $2,
         refresh_token_expires_at = NOW() + ($3::text || ' days')::interval,
         user_agent = $4,
         ip_address = $5,
         last_seen_at = NOW()
     FROM users AS u
     WHERE s.user_id = u.id
       AND s.refresh_token_hash = $1
       AND s.revoked_at IS NULL
       AND s.refresh_token_expires_at > NOW()
     RETURNING s.id, s.token_id, u.id AS user_id, u.email, u.name, u.avatar_url`,
    [
      hashRefreshToken(refreshToken),
      hashRefreshToken(nextRefreshToken),
      refreshTokenDays(),
      cleanUserAgent(req.get('user-agent')),
      requestIp(req),
    ]
  );

  const row = rows[0];
  if (!row) {
    return undefined;
  }

  return {
    sessionId: row.id,
    tokenId: row.token_id,
    refreshToken: nextRefreshToken,
    user: {
      id: row.user_id,
      email: row.email,
      name: row.name,
      avatar_url: row.avatar_url,
    },
  };
}

export async function listAuthSessions(
  userId: string,
  currentSessionId?: string
): Promise<AuthSessionSummary[]> {
  const { rows } = await pool.query(
    `SELECT id, created_at, last_seen_at, user_agent, ip_address, id = $2 AS current_session
     FROM auth_sessions
     WHERE user_id = $1 AND revoked_at IS NULL
     ORDER BY last_seen_at DESC, created_at DESC`,
    [userId, currentSessionId ?? null]
  );

  return rows;
}

export async function revokeAuthSession(userId: string, sessionId: string): Promise<boolean> {
  const { rowCount } = await pool.query(
    `UPDATE auth_sessions
     SET revoked_at = COALESCE(revoked_at, NOW())
     WHERE user_id = $1 AND id = $2`,
    [userId, sessionId]
  );

  return (rowCount ?? 0) > 0;
}

export async function revokeAllAuthSessions(userId: string): Promise<void> {
  await pool.query(
    `UPDATE auth_sessions
     SET revoked_at = COALESCE(revoked_at, NOW())
     WHERE user_id = $1 AND revoked_at IS NULL`,
    [userId]
  );
}

export async function isAuthSessionRevoked(
  userId: string,
  sessionId: string,
  tokenId?: string
): Promise<boolean> {
  const { rows } = await pool.query(
    `SELECT token_id, revoked_at
     FROM auth_sessions
     WHERE user_id = $1 AND id = $2`,
    [userId, sessionId]
  );
  const session = rows[0];
  if (!session || session.revoked_at) {
    return true;
  }

  return Boolean(tokenId) && session.token_id !== tokenId;
}

export async function markAuthSessionSeen(userId: string, sessionId: string): Promise<void> {
  await pool.query(
    `UPDATE auth_sessions
     SET last_seen_at = NOW()
     WHERE user_id = $1
       AND id = $2
       AND revoked_at IS NULL
       AND last_seen_at < NOW() - INTERVAL '5 minutes'`,
    [userId, sessionId]
  );
}

function cleanUserAgent(value: string | undefined): string | null {
  const trimmed = value?.trim();
  if (!trimmed) {
    return null;
  }

  return trimmed.slice(0, MAX_USER_AGENT_LENGTH);
}

function requestIp(req: Request): string | null {
  return req.ip || req.socket.remoteAddress || null;
}

function generateRefreshToken(): string {
  return randomBytes(REFRESH_TOKEN_BYTES).toString('base64url');
}

function hashRefreshToken(refreshToken: string): string {
  return createHash('sha256').update(refreshToken).digest('hex');
}

function refreshTokenDays(): number {
  return getIntegerEnv('REFRESH_TOKEN_EXPIRES_IN_DAYS', DEFAULT_REFRESH_TOKEN_DAYS);
}
