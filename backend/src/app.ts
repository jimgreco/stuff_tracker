import 'express-async-errors';
import * as fs from 'node:fs';
import { randomUUID } from 'node:crypto';
import * as path from 'node:path';
import express, { NextFunction, Request, Response } from 'express';
import cors, { CorsOptions } from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { ZodError } from 'zod';

import { pool } from './db/pool';
import authRouter from './routes/auth';
import accountRouter from './routes/account';
import adminRouter from './routes/admin';
import appStoreRouter from './routes/appStore';
import homesRouter from './routes/homes';
import locationsRouter from './routes/locations';
import itemsRouter from './routes/items';
import { authRateLimit } from './lib/rateLimits';
import { getCsvEnv, isProduction } from './lib/env';
import { sendOperationalAlert } from './lib/alerts';
import { createErrorRateAlertMiddleware } from './lib/errorRateAlerts';

export function createApp() {
  const app = express();

  app.disable('x-powered-by');
  configureTrustProxy(app);

  app.use(helmet({
    contentSecurityPolicy: {
      directives: {
        'connect-src': ["'self'", 'https://accounts.google.com', 'https://appleid.apple.com'],
        'frame-src': ["'self'", 'https://accounts.google.com', 'https://appleid.apple.com'],
        'img-src': ["'self'", 'data:', 'https:'],
        'script-src': ["'self'", 'https://accounts.google.com', 'https://appleid.cdn-apple.com'],
      },
    },
  }));
  app.use(cors(corsOptions()));
  app.use(assignRequestId);
  app.use(httpLogger());
  app.use(createErrorRateAlertMiddleware());
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

  app.get(['/apple-app-site-association', '/.well-known/apple-app-site-association'], (_req, res) => {
    res.type('application/json').send(appleAppSiteAssociation());
  });

  app.use('/auth', authRateLimit, authRouter);
  app.use('/account', accountRouter);
  app.use('/admin', adminRouter);
  app.use('/app-store', appStoreRouter);
  app.use('/homes', homesRouter);
  app.use('/homes/:homeId/locations', locationsRouter);
  app.use('/homes/:homeId/items', itemsRouter);

  configureStaticWeb(app);

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

function configureStaticWeb(app: ReturnType<typeof express>): void {
  const webRoot = staticWebRoot();
  if (!webRoot) {
    return;
  }

  const indexPath = path.join(webRoot, 'index.html');
  const sendIndex = (_req: Request, res: Response) => {
    res.sendFile(indexPath);
  };
  const sendSharedItemIndex = async (req: Request, res: Response) => {
    const metadata = await sharedItemMetadata(req.params.homeId, req.params.itemId);
    if (!metadata) {
      res.sendFile(indexPath);
      return;
    }

    res.type('html').send(sharedItemDocument(
      fs.readFileSync(indexPath, 'utf8'),
      metadata,
      publicBaseUrl(req),
      req.originalUrl
    ));
  };

  app.use(express.static(webRoot, { index: false }));
  app.use('/web', express.static(webRoot, { index: false }));
  app.get(['/items/:homeId/:itemId', '/web/items/:homeId/:itemId'], sendSharedItemIndex);
  app.get(['/', '/web', '/web/'], sendIndex);
}

type SharedItemMetadata = {
  title: string;
  description: string;
};

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

async function sharedItemMetadata(homeId: string, itemId: string): Promise<SharedItemMetadata | undefined> {
  if (!UUID_PATTERN.test(homeId) || !UUID_PATTERN.test(itemId)) {
    return undefined;
  }

  try {
    const { rows } = await pool.query<{
      item_name: string;
      home_name: string;
      location_id: string | null;
    }>(
      `SELECT i.name AS item_name, i.location_id, h.name AS home_name
       FROM items i
       JOIN homes h ON h.id = i.home_id
       WHERE i.home_id = $1 AND i.id = $2
       LIMIT 1`,
      [homeId, itemId]
    );

    const item = rows[0];
    if (!item) {
      return undefined;
    }

    const locationNames = item.location_id
      ? await locationPath(homeId, item.location_id)
      : [];
    const locationText = [item.home_name, ...locationNames].join(' / ');

    return {
      title: `${item.item_name} - ${locationText} | Stuff Tracker`,
      description: `${item.item_name} is in ${locationText}. Open it in Stuff Tracker.`,
    };
  } catch {
    return undefined;
  }
}

async function locationPath(homeId: string, locationId: string): Promise<string[]> {
  const { rows } = await pool.query<{
    id: string;
    parent_id: string | null;
    name: string;
  }>(
    'SELECT id, parent_id, name FROM locations WHERE home_id = $1',
    [homeId]
  );

  const locationsById = new Map(rows.map((row) => [row.id, row]));
  const names: string[] = [];
  const visited = new Set<string>();
  let currentId: string | null = locationId;

  while (currentId && !visited.has(currentId)) {
    const location = locationsById.get(currentId);
    if (!location) {
      break;
    }

    names.unshift(location.name);
    visited.add(currentId);
    currentId = location.parent_id;
  }

  return names;
}

function sharedItemDocument(indexHtml: string, metadata: SharedItemMetadata, baseUrl: string, path: string): string {
  const title = escapeHtml(metadata.title);
  const description = escapeHtml(metadata.description);
  const url = escapeHtml(`${baseUrl}${path}`);
  const imageUrl = escapeHtml(`${baseUrl}/assets/app-icon.png`);
  const socialMetadata = [
    `<meta property="og:type" content="website">`,
    `<meta property="og:site_name" content="Stuff Tracker">`,
    `<meta property="og:title" content="${title}">`,
    `<meta property="og:description" content="${description}">`,
    `<meta property="og:url" content="${url}">`,
    `<meta property="og:image" content="${imageUrl}">`,
    `<meta name="twitter:card" content="summary">`,
    `<meta name="twitter:title" content="${title}">`,
    `<meta name="twitter:description" content="${description}">`,
  ].map((tag) => `    ${tag}`).join('\n');

  return indexHtml
    .replace(/<title>.*?<\/title>/, `<title>${title}</title>`)
    .replace(/<meta name="description" content="[^"]*">/, `<meta name="description" content="${description}">`)
    .replace('</head>', `${socialMetadata}\n  </head>`);
}

function publicBaseUrl(req: Request): string {
  const configured = process.env.APP_BASE_URL?.trim();
  if (configured) {
    return configured.replace(/\/+$/, '');
  }

  return `${req.protocol}://${req.get('host') ?? 'localhost'}`;
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (char) => {
    switch (char) {
      case '&': return '&amp;';
      case '<': return '&lt;';
      case '>': return '&gt;';
      case '"': return '&quot;';
      case "'": return '&#39;';
      default: return char;
    }
  });
}

function appleAppSiteAssociation() {
  return {
    applinks: {
      apps: [],
      details: [
        {
          appID: `${associatedDomainsTeamId()}.${associatedDomainsBundleId()}`,
          paths: ['/items/*'],
        },
      ],
    },
  };
}

function associatedDomainsTeamId(): string {
  return process.env.APPLE_TEAM_ID?.trim() || 'V6JPQCD336';
}

function associatedDomainsBundleId(): string {
  return process.env.APP_STORE_BUNDLE_ID?.trim()
    || process.env.APPLE_BUNDLE_ID?.trim()
    || 'com.jimgreco.stufftracker';
}

function staticWebRoot(): string | undefined {
  const candidates = [
    process.env.STUFF_WEB_DIR,
    path.resolve(__dirname, '../web'),
    path.resolve(__dirname, '../../web'),
  ].filter((candidate): candidate is string => Boolean(candidate));

  return candidates.find((candidate) => fs.existsSync(path.join(candidate, 'index.html')));
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

  const event = {
    timestamp: new Date().toISOString(),
    level: 'error',
    event: 'unhandled_error',
    request_id: requestId,
    error,
  };

  console.error(JSON.stringify(event));
  void sendOperationalAlert({
    level: 'error',
    event: 'unhandled_error',
    request_id: requestId,
    message: error.message,
    error,
  });
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
