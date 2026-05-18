import 'express-async-errors';
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
  app.use(morgan(isProduction() ? 'combined' : 'short'));
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

    console.error(err);
    res.status(500).json({ error: 'Internal server error' });
  });

  return app;
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
