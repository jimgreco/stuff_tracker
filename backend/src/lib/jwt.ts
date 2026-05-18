import jwt from 'jsonwebtoken';
import { assertStrongJwtSecret, getRequiredEnv } from './env';

const EXPIRES_IN = '90d';

export interface JwtPayload {
  userId: string;
  email: string;
}

export function signToken(payload: JwtPayload): string {
  return jwt.sign(payload, jwtSecret(), { expiresIn: EXPIRES_IN });
}

export function verifyToken(token: string): JwtPayload {
  return jwt.verify(token, jwtSecret()) as JwtPayload;
}

function jwtSecret(): string {
  const secret = getRequiredEnv('JWT_SECRET');
  assertStrongJwtSecret(secret);
  return secret;
}
