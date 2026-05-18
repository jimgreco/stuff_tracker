import { PoolClient } from 'pg';
import { pool } from '../db/pool';

export interface UserRow {
  id: string;
  email: string;
  name: string;
  avatar_url: string | null;
  google_id?: string | null;
  apple_id?: string | null;
}

export class UserIdentityConflictError extends Error {
  constructor(message = 'This identity is already linked to another account') {
    super(message);
    this.name = 'UserIdentityConflictError';
  }
}

interface UpsertUserParams {
  googleId?: string;
  appleId?: string;
  email: string;
  name: string;
  avatarUrl?: string;
  emailIsFallback?: boolean;
}

type Queryable = Pick<PoolClient, 'query'>;
type ProviderColumn = 'google_id' | 'apple_id';

export async function upsertUser(params: UpsertUserParams): Promise<UserRow> {
  const client = await pool.connect();

  try {
    await client.query('BEGIN');
    const user = await upsertUserWithClient(client, params);
    await client.query('COMMIT');
    return user;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

export async function upsertUserWithClient(client: Queryable, params: UpsertUserParams): Promise<UserRow> {
  const email = normalizeEmail(params.email);
  const provider = providerFor(params);

  if (provider) {
    const byProvider = await client.query<UserRow>(
      `SELECT id, email, name, avatar_url, google_id, apple_id
       FROM users
       WHERE ${provider.column} = $1
       FOR UPDATE`,
      [provider.value]
    );

    if (byProvider.rows[0]) {
      return updateExistingUser(client, byProvider.rows[0], { ...params, email });
    }
  }

  const byEmail = await client.query<UserRow>(
    `SELECT id, email, name, avatar_url, google_id, apple_id
     FROM users
     WHERE email = $1
     FOR UPDATE`,
    [email]
  );

  if (byEmail.rows[0]) {
    return updateExistingUser(client, byEmail.rows[0], { ...params, email });
  }

  const inserted = await client.query<UserRow>(
    `INSERT INTO users (email, name, avatar_url, google_id, apple_id)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING id, email, name, avatar_url, google_id, apple_id`,
    [email, params.name, params.avatarUrl ?? null, params.googleId ?? null, params.appleId ?? null]
  );

  return inserted.rows[0];
}

function providerFor(params: UpsertUserParams): { column: ProviderColumn; value: string } | undefined {
  if (params.googleId) {
    return { column: 'google_id', value: params.googleId };
  }

  if (params.appleId) {
    return { column: 'apple_id', value: params.appleId };
  }

  return undefined;
}

async function updateExistingUser(
  client: Queryable,
  existing: UserRow,
  params: UpsertUserParams & { email: string }
): Promise<UserRow> {
  if (params.googleId && existing.google_id && existing.google_id !== params.googleId) {
    throw new UserIdentityConflictError();
  }

  if (params.appleId && existing.apple_id && existing.apple_id !== params.appleId) {
    throw new UserIdentityConflictError();
  }

  const nextEmail = shouldUpdateEmail(existing.email, params.email, params.emailIsFallback)
    ? params.email
    : existing.email;
  const safeEmail = await availableEmailForUser(client, existing.id, nextEmail, existing.email);

  const updated = await client.query<UserRow>(
    `UPDATE users
     SET email = $2,
         name = $3,
         avatar_url = COALESCE($4, avatar_url),
         google_id = COALESCE(google_id, $5),
         apple_id = COALESCE(apple_id, $6),
         updated_at = NOW()
     WHERE id = $1
     RETURNING id, email, name, avatar_url, google_id, apple_id`,
    [
      existing.id,
      safeEmail,
      params.name || existing.name,
      params.avatarUrl ?? null,
      params.googleId ?? null,
      params.appleId ?? null,
    ]
  );

  return updated.rows[0];
}

async function availableEmailForUser(
  client: Queryable,
  userId: string,
  nextEmail: string,
  existingEmail: string
): Promise<string> {
  if (nextEmail === existingEmail) {
    return existingEmail;
  }

  const { rows } = await client.query<{ id: string }>(
    'SELECT id FROM users WHERE email = $1 AND id <> $2 LIMIT 1',
    [nextEmail, userId]
  );

  return rows[0] ? existingEmail : nextEmail;
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

function shouldUpdateEmail(existingEmail: string, nextEmail: string, isFallback = false): boolean {
  if (existingEmail === nextEmail) {
    return false;
  }

  return !isFallback;
}
