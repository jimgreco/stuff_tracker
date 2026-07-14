import { Router, Response } from 'express';
import { pool } from '../db/pool';
import { requireAuth, AuthRequest } from '../middleware/auth';
import { getHomeRole } from '../lib/access';

const router = Router({ mergeParams: true });
router.use(requireAuth);

router.get('/', async (req: AuthRequest, res: Response) => {
  const { homeId } = req.params;
  if (!await getHomeRole(homeId, req.user!.userId)) {
    res.status(403).json({ error: 'Access denied' });
    return;
  }

  const limit = Math.min(Math.max(Number(req.query.limit) || 50, 1), 100);
  const values: unknown[] = [homeId];
  const conditions = ['home_id = $1'];
  const add = (sql: string, value: unknown) => {
    values.push(value);
    conditions.push(sql.replace('?', `$${values.length}`));
  };

  if (req.query.actor_id) add('actor_id = ?', String(req.query.actor_id));
  if (req.query.action) add('action = ?', String(req.query.action));
  if (req.query.entity_type) add('entity_type = ?', String(req.query.entity_type));
  if (req.query.entity_id) add('entity_id = ?', String(req.query.entity_id));
  if (req.query.from) add('created_at >= ?', String(req.query.from));
  if (req.query.to) add('created_at <= ?', String(req.query.to));

  const cursor = decodeCursor(String(req.query.cursor ?? ''));
  if (cursor) {
    values.push(cursor.createdAt, cursor.id);
    conditions.push(`(created_at, id) < ($${values.length - 1}::timestamptz, $${values.length}::uuid)`);
  }
  values.push(limit + 1);

  const [{ rows }, actorResult] = await Promise.all([pool.query(
    `SELECT id, home_id, actor_id, actor_name, actor_email, action, entity_type,
            entity_id, entity_name, location_path, summary, changes,
            client_occurred_at, created_at,
            (client_occurred_at IS NOT NULL AND client_occurred_at < created_at - INTERVAL '5 minutes') AS is_offline_change
     FROM home_activity_events
     WHERE ${conditions.join(' AND ')}
     ORDER BY created_at DESC, id DESC
     LIMIT $${values.length}`,
    values
  ), pool.query(
    `SELECT DISTINCT ON (actor_id) actor_id AS id,
            COALESCE(actor_name, actor_email, 'Unknown person') AS name
     FROM home_activity_events
     WHERE home_id = $1 AND actor_id IS NOT NULL
     ORDER BY actor_id, created_at DESC`,
    [homeId]
  )]);

  const hasMore = rows.length > limit;
  const events = rows.slice(0, limit);
  const last = events.at(-1);
  res.json({
    events,
    next_cursor: hasMore && last ? encodeCursor(last.created_at, last.id) : null,
    retention_days: 365,
    actors: actorResult.rows,
  });
});

function encodeCursor(createdAt: string | Date, id: string): string {
  return Buffer.from(JSON.stringify({ createdAt, id })).toString('base64url');
}

function decodeCursor(value: string): { createdAt: string; id: string } | null {
  if (!value) return null;
  try {
    const parsed = JSON.parse(Buffer.from(value, 'base64url').toString('utf8'));
    return typeof parsed.createdAt === 'string' && typeof parsed.id === 'string' ? parsed : null;
  } catch {
    return null;
  }
}

export default router;
