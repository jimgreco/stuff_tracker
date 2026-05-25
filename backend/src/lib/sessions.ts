import { Request } from 'express';
import { pool } from '../db/pool';

const MAX_USER_AGENT_LENGTH = 500;

export interface CreatedAuthSession {
  sessionId: string;
  tokenId: string;
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
  const { rows } = await pool.query(
    `INSERT INTO auth_sessions (user_id, user_agent, ip_address)
     VALUES ($1, $2, $3)
     RETURNING id, token_id`,
    [userId, cleanUserAgent(req.get('user-agent')), requestIp(req)]
  );

  return {
    sessionId: rows[0].id,
    tokenId: rows[0].token_id,
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
