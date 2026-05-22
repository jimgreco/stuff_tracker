import { Request, Response, NextFunction } from 'express';
import { verifyToken, JwtPayload } from '../lib/jwt';
import { pool } from '../db/pool';

export interface AuthRequest extends Request {
  user?: JwtPayload;
}

export async function requireAuth(req: AuthRequest, res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Missing or invalid Authorization header' });
    return;
  }
  const token = header.slice(7);
  let payload: JwtPayload;
  try {
    payload = verifyToken(token);
  } catch {
    res.status(401).json({ error: 'Invalid or expired token' });
    return;
  }

  try {
    if (await isRevoked(payload)) {
      res.status(401).json({ error: 'Invalid or expired token' });
      return;
    }
  } catch (err) {
    next(err);
    return;
  }

  req.user = payload;
  next();
}

async function isRevoked(payload: JwtPayload): Promise<boolean> {
  if (process.env.SKIP_TOKEN_REVOCATION_CHECKS === 'true') {
    return false;
  }

  if (process.env.NODE_ENV === 'test' && process.env.RUN_DATABASE_INTEGRATION_TESTS !== 'true') {
    return false;
  }

  const { rows } = await pool.query(
    'SELECT tokens_revoked_before FROM users WHERE id = $1',
    [payload.userId]
  );
  const user = rows[0];
  if (!user) {
    return true;
  }

  if (!user.tokens_revoked_before) {
    return false;
  }

  if (!payload.iat) {
    return true;
  }

  return payload.iat * 1000 <= new Date(user.tokens_revoked_before).getTime();
}
