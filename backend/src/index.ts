import 'express-async-errors';
import dotenv from 'dotenv';
dotenv.config();

import express, { Request, Response, NextFunction } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { ZodError } from 'zod';

import authRouter from './routes/auth';
import homesRouter from './routes/homes';
import locationsRouter from './routes/locations';
import itemsRouter from './routes/items';

const app = express();

app.use(helmet());
app.use(cors());
app.use(morgan('short'));
app.use(express.json({ limit: '2mb' }));

// ── Routes ─────────────────────────────────────────────────────────────────────
app.use('/auth', authRouter);
app.use('/homes', homesRouter);
app.use('/homes/:homeId/locations', locationsRouter);
app.use('/homes/:homeId/items', itemsRouter);

app.get('/health', (_req, res) => res.json({ ok: true }));

// ── Error handler ──────────────────────────────────────────────────────────────
app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
  if (err instanceof ZodError) {
    res.status(400).json({ error: 'Validation error', details: err.errors });
    return;
  }
  console.error(err);
  res.status(500).json({ error: 'Internal server error' });
});

const PORT = Number(process.env.PORT ?? 3002);
app.listen(PORT, () => console.log(`stuff-tracker API listening on :${PORT}`));
