import { rateLimit } from 'express-rate-limit';
import { getIntegerEnv } from './env';

export const authRateLimit = rateLimit({
  windowMs: getIntegerEnv('AUTH_RATE_LIMIT_WINDOW_MS', 15 * 60 * 1000),
  limit: getIntegerEnv('AUTH_RATE_LIMIT_MAX', 50),
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { error: 'Too many authentication attempts. Please try again later.' },
});

export const uploadRateLimit = rateLimit({
  windowMs: getIntegerEnv('UPLOAD_RATE_LIMIT_WINDOW_MS', 15 * 60 * 1000),
  limit: getIntegerEnv('UPLOAD_RATE_LIMIT_MAX', 100),
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { error: 'Too many upload requests. Please try again later.' },
});
