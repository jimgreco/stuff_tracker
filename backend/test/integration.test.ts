import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import net from 'node:net';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createApp } from '../src/app';
import { pool } from '../src/db/pool';
import { upsertUser } from '../src/lib/users';

process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = process.env.JWT_SECRET ?? 'unit-test-secret-that-is-long-enough';
process.env.GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID ?? 'test-google-client-id';
process.env.APPLE_BUNDLE_ID = process.env.APPLE_BUNDLE_ID ?? 'com.jimgreco.stufftracker';

const runDatabaseIntegrationTests = process.env.RUN_DATABASE_INTEGRATION_TESTS === 'true'
  && Boolean(process.env.DATABASE_URL);
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const migrationsDir = path.resolve(__dirname, '..', 'src', 'db', 'migrations');

test.after(async () => {
  if (runDatabaseIntegrationTests) {
    await pool.end();
  }
});

test('dev auth and homes API work against a real database', { skip: !runDatabaseIntegrationTests }, async (t) => {
  await resetDatabase();

  const server = await listen();
  t.after(() => close(server));
  const baseUrl = serverBaseUrl(server);

  const unauthorized = await fetch(`${baseUrl}/homes`);
  assert.equal(unauthorized.status, 401);

  const auth = await postJson(`${baseUrl}/auth/dev`, {
    email: 'integration@example.com',
    name: 'Integration User',
  });
  assert.equal(auth.status, 200);
  const authBody = await auth.json() as { token: string; user: { email: string } };
  assert.equal(authBody.user.email, 'integration@example.com');
  assert.ok(authBody.token);

  const created = await postJson(
    `${baseUrl}/homes`,
    { name: 'Integration Home', icon: 'house.fill' },
    authBody.token
  );
  assert.equal(created.status, 201);
  const createdBody = await created.json() as { id: string; role: string };
  assert.ok(createdBody.id);
  assert.equal(createdBody.role, 'owner');

  const homes = await fetch(`${baseUrl}/homes`, {
    headers: { Authorization: `Bearer ${authBody.token}` },
  });
  assert.equal(homes.status, 200);
  const homeRows = await homes.json() as Array<{ id: string; name: string }>;
  assert.deepEqual(homeRows.map((home) => home.name), ['Integration Home']);

  const sessions = await fetch(`${baseUrl}/auth/sessions`, {
    headers: { Authorization: `Bearer ${authBody.token}` },
  });
  assert.equal(sessions.status, 200);
  const sessionRows = await sessions.json() as Array<{ id: string; current_session: boolean }>;
  assert.equal(sessionRows.length, 1);
  assert.equal(sessionRows[0].current_session, true);

  const secondAuth = await postJson(`${baseUrl}/auth/dev`, {
    email: 'integration@example.com',
    name: 'Integration User',
  });
  assert.equal(secondAuth.status, 200);
  const secondAuthBody = await secondAuth.json() as { token: string };

  const twoSessions = await fetch(`${baseUrl}/auth/sessions`, {
    headers: { Authorization: `Bearer ${secondAuthBody.token}` },
  });
  assert.equal(twoSessions.status, 200);
  const twoSessionRows = await twoSessions.json() as Array<{ id: string; current_session: boolean }>;
  assert.equal(twoSessionRows.length, 2);
  const previousSession = twoSessionRows.find((session) => !session.current_session);
  assert.ok(previousSession);

  const revokePrevious = await fetch(`${baseUrl}/auth/sessions/${previousSession.id}`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${secondAuthBody.token}` },
  });
  assert.equal(revokePrevious.status, 204);

  const revokedPreviousHomes = await fetch(`${baseUrl}/homes`, {
    headers: { Authorization: `Bearer ${authBody.token}` },
  });
  assert.equal(revokedPreviousHomes.status, 401);

  const health = await fetch(`${baseUrl}/health`);
  assert.equal(health.status, 200);
  assert.deepEqual(await health.json(), { ok: true, db: true });

  const logoutAll = await fetch(`${baseUrl}/auth/logout-all`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${secondAuthBody.token}` },
  });
  assert.equal(logoutAll.status, 204);

  const revokedHomes = await fetch(`${baseUrl}/homes`, {
    headers: { Authorization: `Bearer ${secondAuthBody.token}` },
  });
  assert.equal(revokedHomes.status, 401);
});

test('provider upsert preserves an existing Apple email when later tokens omit it', { skip: !runDatabaseIntegrationTests }, async () => {
  await resetDatabase();

  const first = await upsertUser({
    appleId: 'apple-sub-1',
    email: 'real-private-relay@privaterelay.appleid.com',
    name: 'Jane Appleseed',
  });
  const second = await upsertUser({
    appleId: 'apple-sub-1',
    email: 'apple-sub-1@privaterelay.appleid.com',
    name: 'Jane Appleseed',
    emailIsFallback: true,
  });

  assert.equal(second.id, first.id);
  assert.equal(second.email, 'real-private-relay@privaterelay.appleid.com');
});

async function resetDatabase() {
  await pool.query('DROP SCHEMA public CASCADE');
  await pool.query('CREATE SCHEMA public');

  const files = fs.readdirSync(migrationsDir).filter((file) => file.endsWith('.sql')).sort();
  for (const file of files) {
    await pool.query(fs.readFileSync(path.join(migrationsDir, file), 'utf8'));
  }
}

async function listen(): Promise<http.Server> {
  const app = createApp();
  const server = app.listen(0, '127.0.0.1');
  await new Promise<void>((resolve) => server.once('listening', resolve));
  return server;
}

function close(server: http.Server): Promise<void> {
  return new Promise((resolve, reject) => {
    server.close((err) => err ? reject(err) : resolve());
  });
}

function serverBaseUrl(server: http.Server): string {
  const address = server.address() as net.AddressInfo;
  return `http://127.0.0.1:${address.port}`;
}

function postJson(url: string, body: unknown, token?: string): Promise<Response> {
  return fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
}
