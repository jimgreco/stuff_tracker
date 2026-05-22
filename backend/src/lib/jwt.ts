import jwt from 'jsonwebtoken';
import { assertStrongJwtSecret, getRequiredEnv } from './env';

const DEFAULT_EXPIRES_IN = '90d';

export interface JwtPayload {
  userId: string;
  email: string;
  iat?: number;
}

export function signToken(payload: JwtPayload): string {
  return jwt.sign(payload, jwtSecret(), { expiresIn: jwtExpiresIn() as jwt.SignOptions['expiresIn'] });
}

export function verifyToken(token: string): JwtPayload {
  return jwt.verify(token, jwtSecret()) as JwtPayload;
}

function jwtSecret(): string {
  const secret = getRequiredEnv('JWT_SECRET');
  assertStrongJwtSecret(secret);
  return secret;
}

function jwtExpiresIn(): string {
  return process.env.JWT_EXPIRES_IN?.trim() || DEFAULT_EXPIRES_IN;
}
