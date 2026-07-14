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
  const authBody = await auth.json() as { token: string; refreshToken: string; user: { email: string } };
  assert.equal(authBody.user.email, 'integration@example.com');
  assert.ok(authBody.token);
  assert.ok(authBody.refreshToken);

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

  const refresh = await postJson(`${baseUrl}/auth/refresh`, {
    refreshToken: authBody.refreshToken,
  });
  assert.equal(refresh.status, 200);
  const refreshedAuthBody = await refresh.json() as { token: string; refreshToken: string; user: { email: string } };
  assert.equal(refreshedAuthBody.user.email, 'integration@example.com');
  assert.ok(refreshedAuthBody.token);
  assert.ok(refreshedAuthBody.refreshToken);
  assert.notEqual(refreshedAuthBody.refreshToken, authBody.refreshToken);

  const reusedRefresh = await postJson(`${baseUrl}/auth/refresh`, {
    refreshToken: authBody.refreshToken,
  });
  assert.equal(reusedRefresh.status, 401);

  const rotatedAccessToken = await fetch(`${baseUrl}/homes`, {
    headers: { Authorization: `Bearer ${authBody.token}` },
  });
  assert.equal(rotatedAccessToken.status, 401);

  const refreshedHomes = await fetch(`${baseUrl}/homes`, {
    headers: { Authorization: `Bearer ${refreshedAuthBody.token}` },
  });
  assert.equal(refreshedHomes.status, 200);

  const sessions = await fetch(`${baseUrl}/auth/sessions`, {
    headers: { Authorization: `Bearer ${refreshedAuthBody.token}` },
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
    headers: { Authorization: `Bearer ${refreshedAuthBody.token}` },
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

test('shared-home activity is transactional, scoped, stable, idempotent, and redacted', { skip: !runDatabaseIntegrationTests }, async (t) => {
  await resetDatabase();
  const server = await listen();
  t.after(() => close(server));
  const baseUrl = serverBaseUrl(server);

  const ownerAuth = await postJson(`${baseUrl}/auth/dev`, { email: 'activity-owner@example.com', name: 'Activity Owner' });
  const owner = await ownerAuth.json() as { token: string; user: { id: string } };
  const memberAuth = await postJson(`${baseUrl}/auth/dev`, { email: 'activity-member@example.com', name: 'Activity Member' });
  const member = await memberAuth.json() as { token: string; user: { id: string } };
  await pool.query(
    `INSERT INTO user_entitlements (user_id, source, status) VALUES ($1, 'manual', 'active')`,
    [owner.user.id]
  );

  const createdHome = await fetch(`${baseUrl}/homes`, {
    method: 'POST',
    headers: activityHeaders(owner.token, 'create-home', '2026-01-01T00:00:00.000Z'),
    body: JSON.stringify({ name: 'Audit Home', icon: 'house.fill' }),
  });
  assert.equal(createdHome.status, 201);
  const home = await createdHome.json() as { id: string };

  const addedMember = await fetch(`${baseUrl}/homes/${home.id}/members`, {
    method: 'POST',
    headers: activityHeaders(owner.token, 'add-member'),
    body: JSON.stringify({ email: 'activity-member@example.com', role: 'editor' }),
  });
  assert.equal(addedMember.status, 201);

  const createdLocation = await fetch(`${baseUrl}/homes/${home.id}/locations`, {
    method: 'POST', headers: activityHeaders(owner.token, 'create-location'),
    body: JSON.stringify({ name: 'Office', type: 'room', sort_order: 0 }),
  });
  assert.equal(createdLocation.status, 201);
  const location = await createdLocation.json() as { id: string };

  const createdItem = await fetch(`${baseUrl}/homes/${home.id}/items`, {
    method: 'POST', headers: activityHeaders(owner.token, 'create-item'),
    body: JSON.stringify({ name: 'Router', location_id: location.id, quantity: 1 }),
  });
  assert.equal(createdItem.status, 201);
  const item = await createdItem.json() as { id: string };

  const secret = 'do-not-store-this-private-note';
  for (const quantity of [2, 2]) {
    const updated = await fetch(`${baseUrl}/homes/${home.id}/items/${item.id}`, {
      method: 'PATCH', headers: activityHeaders(owner.token, 'retry-safe-update'),
      body: JSON.stringify({ quantity, notes: secret, serial_number: 'SECRET-SERIAL' }),
    });
    assert.equal(updated.status, 200);
  }
  const duplicateEvents = await pool.query(
    `SELECT COUNT(*)::int AS count FROM home_activity_events WHERE mutation_id = 'retry-safe-update'`
  );
  assert.equal(duplicateEvents.rows[0].count, 1);

  const beforeFailure = await pool.query('SELECT COUNT(*)::int AS count FROM home_activity_events');
  const failed = await fetch(`${baseUrl}/homes/${home.id}/items/${item.id}`, {
    method: 'PATCH', headers: activityHeaders(owner.token, 'failed-update'),
    body: JSON.stringify({ quantity: 0 }),
  });
  assert.equal(failed.status, 400);
  const afterFailure = await pool.query('SELECT COUNT(*)::int AS count FROM home_activity_events');
  assert.equal(afterFailure.rows[0].count, beforeFailure.rows[0].count);

  const firstPage = await fetch(`${baseUrl}/homes/${home.id}/activity?limit=1`, {
    headers: { Authorization: `Bearer ${member.token}` },
  });
  assert.equal(firstPage.status, 200);
  const first = await firstPage.json() as { events: Array<Record<string, unknown>>; next_cursor: string };
  assert.equal(first.events.length, 1);
  assert.ok(first.next_cursor);
  const secondPage = await fetch(`${baseUrl}/homes/${home.id}/activity?limit=1&cursor=${encodeURIComponent(first.next_cursor)}`, {
    headers: { Authorization: `Bearer ${member.token}` },
  });
  const second = await secondPage.json() as { events: Array<Record<string, unknown>> };
  assert.equal(second.events.length, 1);
  assert.notEqual(second.events[0].id, first.events[0].id);

  const itemHistory = await fetch(`${baseUrl}/homes/${home.id}/activity?entity_id=${item.id}`, {
    headers: { Authorization: `Bearer ${owner.token}` },
  });
  const itemPage = await itemHistory.json() as { events: Array<{ entity_name: string; is_offline_change: boolean; changes: unknown }> };
  assert.ok(itemPage.events.length >= 2);
  assert.ok(itemPage.events.every((event) => event.entity_name === 'Router'));
  const serialized = JSON.stringify(itemPage);
  assert.doesNotMatch(serialized, new RegExp(secret));
  assert.doesNotMatch(serialized, /SECRET-SERIAL/);

  const allActivity = await fetch(`${baseUrl}/homes/${home.id}/activity`, {
    headers: { Authorization: `Bearer ${owner.token}` },
  });
  const allPage = await allActivity.json() as { events: Array<{ action: string; is_offline_change: boolean }> };
  assert.ok(allPage.events.some((event) => event.action === 'member_added'));
  assert.ok(allPage.events.some((event) => event.is_offline_change));

  const removed = await fetch(`${baseUrl}/homes/${home.id}/members/${member.user.id}`, {
    method: 'DELETE', headers: activityHeaders(owner.token, 'remove-member'),
  });
  assert.equal(removed.status, 204);
  const revokedFeed = await fetch(`${baseUrl}/homes/${home.id}/activity`, {
    headers: { Authorization: `Bearer ${member.token}` },
  });
  assert.equal(revokedFeed.status, 403);

  const deleted = await fetch(`${baseUrl}/homes/${home.id}/items/${item.id}`, {
    method: 'DELETE', headers: activityHeaders(owner.token, 'delete-item'),
  });
  assert.equal(deleted.status, 204);
  const deletion = await pool.query(
    `SELECT entity_name, summary FROM home_activity_events WHERE mutation_id = 'delete-item'`
  );
  assert.deepEqual(deletion.rows[0], { entity_name: 'Router', summary: 'Deleted Router' });
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

function activityHeaders(token: string, mutationId: string, occurredAt = new Date().toISOString()): Record<string, string> {
  return {
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
    'X-CubbyLog-Mutation-ID': mutationId,
    'X-CubbyLog-Occurred-At': occurredAt,
  };
}
