import 'express-async-errors';
import { randomUUID } from 'node:crypto';
import express, { NextFunction, Request, Response } from 'express';
import cors, { CorsOptions } from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { ZodError } from 'zod';

import { pool } from './db/pool';
import authRouter from './routes/auth';
import homesRouter from './routes/homes';
import locationsRouter from './routes/locations';
import itemsRouter from './routes/items';
import { authRateLimit } from './lib/rateLimits';
import { getCsvEnv, isProduction } from './lib/env';

export function createApp() {
  const app = express();

  app.disable('x-powered-by');
  configureTrustProxy(app);

  app.use(helmet());
  app.use(cors(corsOptions()));
  app.use(assignRequestId);
  app.use(httpLogger());
  app.use(express.json({ limit: '2mb' }));

  app.get('/health/live', (_req, res) => res.json({ ok: true }));
  app.get('/health', async (_req, res) => {
    try {
      await pool.query('SELECT 1');
      res.json({ ok: true, db: true });
    } catch {
      res.status(503).json({ ok: false, db: false });
    }
  });

  app.use('/auth', authRateLimit, authRouter);
  app.use('/homes', homesRouter);
  app.use('/homes/:homeId/locations', locationsRouter);
  app.use('/homes/:homeId/items', itemsRouter);

  app.use((_req, res) => {
    res.status(404).json({ error: 'Not found' });
  });

  app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    if (err instanceof ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }

    logError(err, res.locals.requestId);
    res.status(500).json({ error: 'Internal server error' });
  });

  return app;
}

const REQUEST_ID_PATTERN = /^[a-zA-Z0-9._:-]{1,128}$/;

function assignRequestId(req: Request, res: Response, next: NextFunction): void {
  const header = req.header('x-request-id');
  const requestId = header && REQUEST_ID_PATTERN.test(header) ? header : randomUUID();
  res.locals.requestId = requestId;
  res.setHeader('x-request-id', requestId);
  next();
}

function httpLogger() {
  if (process.env.NODE_ENV === 'test') {
    return (_req: Request, _res: Response, next: NextFunction) => next();
  }

  if (!isProduction()) {
    return morgan('short');
  }

  return morgan((tokens, req: Request, res: Response) => JSON.stringify({
    timestamp: new Date().toISOString(),
    level: Number(tokens.status(req, res)) >= 500 ? 'error' : 'info',
    event: 'http_request',
    request_id: res.locals.requestId,
    method: req.method,
    path: req.path,
    status: Number(tokens.status(req, res)),
    duration_ms: Number(tokens['response-time'](req, res)),
    content_length: tokens.res(req, res, 'content-length') ?? null,
    remote_addr: tokens['remote-addr'](req, res),
    user_agent: tokens['user-agent'](req, res) ?? null,
  }));
}

function logError(err: unknown, requestId: string | undefined): void {
  if (!isProduction()) {
    console.error(err);
    return;
  }

  const error = err instanceof Error
    ? { name: err.name, message: err.message, stack: err.stack }
    : { name: 'UnknownError', message: String(err) };

  console.error(JSON.stringify({
    timestamp: new Date().toISOString(),
    level: 'error',
    event: 'unhandled_error',
    request_id: requestId,
    error,
  }));
}

function corsOptions(): CorsOptions {
  const configuredOrigins = getCsvEnv('CORS_ORIGINS');
  const developmentOrigins = isProduction()
    ? []
    : [
        'http://localhost:3000',
        'http://localhost:5173',
        'http://127.0.0.1:3000',
        'http://127.0.0.1:5173',
      ];
  const allowedOrigins = new Set([...configuredOrigins, ...developmentOrigins]);

  return {
    origin(origin, callback) {
      if (!origin) {
        callback(null, true);
        return;
      }

      callback(null, allowedOrigins.has(origin));
    },
    methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Authorization', 'Content-Type'],
    maxAge: 600,
  };
}

function configureTrustProxy(app: ReturnType<typeof express>): void {
  const raw = process.env.TRUST_PROXY?.trim();
  if (!raw) {
    return;
  }

  if (/^\d+$/.test(raw)) {
    app.set('trust proxy', Number(raw));
    return;
  }

  if (raw === 'true') {
    app.set('trust proxy', 1);
    return;
  }

  app.set('trust proxy', raw.includes(',') ? raw.split(',').map((part) => part.trim()) : raw);
}
