import type { PoolClient } from 'pg';
import type { AuthRequest } from '../middleware/auth';
import { pool } from '../db/pool';

const MUTATION_ID_HEADER = 'x-cubbylog-mutation-id';
const OCCURRED_AT_HEADER = 'x-cubbylog-occurred-at';

export async function withActivityTransaction<T>(
  req: AuthRequest,
  work: (client: PoolClient) => Promise<T>
): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await setActivityContext(client, req);
    const result = await work(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function setActivityContext(client: PoolClient, req: AuthRequest): Promise<void> {
  const mutationId = cleanHeader(req.get(MUTATION_ID_HEADER), 200);
  const occurredAt = validTimestamp(req.get(OCCURRED_AT_HEADER));
  await client.query(
    `SELECT set_config('app.activity_actor_id', $1, true),
            set_config('app.activity_mutation_id', $2, true),
            set_config('app.activity_occurred_at', $3, true)`,
    [req.user!.userId, mutationId, occurredAt]
  );
}

function cleanHeader(value: string | undefined, maxLength: number): string {
  return value?.trim().slice(0, maxLength) ?? '';
}

function validTimestamp(value: string | undefined): string {
  if (!value) return '';
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? new Date(parsed).toISOString() : '';
}
