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

test('account deletion removes owned data and sessions while preserving shared-home items without identity', { skip: !runDatabaseIntegrationTests }, async (t) => {
  await resetDatabase();
  const server = await listen();
  t.after(() => close(server));
  const baseUrl = serverBaseUrl(server);

  const firstAuth = await postJson(`${baseUrl}/auth/dev`, { email: 'delete-me@example.com', name: 'Delete Me' });
  const first = await firstAuth.json() as { token: string; refreshToken: string; user: { id: string } };
  const secondAuth = await postJson(`${baseUrl}/auth/dev`, { email: 'stay@example.com', name: 'Stay' });
  const second = await secondAuth.json() as { token: string; user: { id: string } };
  const ownedHomeResponse = await postJson(`${baseUrl}/homes`, { name: 'Delete Home' }, first.token);
  const ownedHome = await ownedHomeResponse.json() as { id: string };
  const sharedHomeResponse = await postJson(`${baseUrl}/homes`, { name: 'Keep Home' }, second.token);
  const sharedHome = await sharedHomeResponse.json() as { id: string };
  await pool.query(
    `INSERT INTO home_members (home_id, user_id, role, invited_by)
     VALUES ($1, $2, 'editor', $3), ($4, $3, 'viewer', $2)`,
    [sharedHome.id, first.user.id, second.user.id, ownedHome.id]
  );
  await pool.query(
    `INSERT INTO items (home_id, name, created_by) VALUES ($1, 'Shared Item', $2)`,
    [sharedHome.id, first.user.id]
  );
  await pool.query(
    `INSERT INTO home_activity_events
     (home_id, actor_id, actor_name, actor_email, action, entity_type, entity_id, entity_name, summary, event_scope)
     VALUES ($1, $2, 'Delete Me', 'delete-me@example.com', 'member_added', 'member', $2, 'Delete Me', 'Added Delete Me', 'test-member')`,
    [sharedHome.id, first.user.id]
  );
  await pool.query(
    `INSERT INTO app_store_transactions
     (transaction_id, original_transaction_id, user_id, product_id, environment, signed_transaction_info, payload)
     VALUES ('test-transaction', 'test-original', $1, 'test-product', 'Sandbox', 'signed', '{}')`,
    [first.user.id]
  );

  const noConfirmation = await fetch(`${baseUrl}/account`, {
    method: 'DELETE', headers: { Authorization: `Bearer ${first.token}` },
  });
  assert.equal(noConfirmation.status, 400);
  const deletion = await fetch(`${baseUrl}/account`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${first.token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ confirmation: 'DELETE' }),
  });
  assert.equal(deletion.status, 204);
  assert.equal((await pool.query('SELECT COUNT(*)::int AS count FROM users WHERE id = $1', [first.user.id])).rows[0].count, 0);
  assert.equal((await pool.query('SELECT COUNT(*)::int AS count FROM homes WHERE id = $1', [ownedHome.id])).rows[0].count, 0);
  assert.equal((await pool.query('SELECT COUNT(*)::int AS count FROM app_store_transactions WHERE user_id = $1', [first.user.id])).rows[0].count, 0);
  const sharedItem = await pool.query('SELECT created_by FROM items WHERE home_id = $1', [sharedHome.id]);
  assert.equal(sharedItem.rows.length, 1);
  assert.equal(sharedItem.rows[0].created_by, null);
  const sharedActivity = await pool.query(
    'SELECT actor_id, actor_name, actor_email, entity_id, entity_name, summary FROM home_activity_events WHERE event_scope = $1',
    ['test-member']
  );
  assert.deepEqual(sharedActivity.rows[0], {
    actor_id: null, actor_name: null, actor_email: null, entity_id: null,
    entity_name: 'Former member', summary: 'Member changed',
  });
  assert.equal((await pool.query('SELECT COUNT(*)::int AS count FROM home_activity_events WHERE home_id = $1', [ownedHome.id])).rows[0].count, 0);
  assert.equal((await fetch(`${baseUrl}/homes`, { headers: { Authorization: `Bearer ${first.token}` } })).status, 401);
  assert.equal((await postJson(`${baseUrl}/auth/refresh`, { refreshToken: first.refreshToken })).status, 401);
  assert.equal((await fetch(`${baseUrl}/homes`, { headers: { Authorization: `Bearer ${second.token}` } })).status, 200);
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

test('attachment adoption and cleanup serialize both race orders against real Postgres', { skip: !runDatabaseIntegrationTests }, async () => {
  await resetDatabase();
  const { lockAttachmentReferences, assertAttachmentsAvailable, deleteUnreferenced } = require('../scripts/lib/attachment-gc.cjs');
  const user = (await pool.query("INSERT INTO users (email, name) VALUES ('gc-race@example.test', 'Synthetic GC') RETURNING id")).rows[0];
  const home = (await pool.query("INSERT INTO homes (owner_id, name) VALUES ($1, 'GC race') RETURNING id", [user.id])).rows[0];
  const adopted = `homes/${home.id}/items/photos/adopted.jpg`;
  const retired = `homes/${home.id}/items/photos/retired.jpg`;
  const writer = await pool.connect();
  let deletes = 0;
  try {
    await writer.query('BEGIN');
    await lockAttachmentReferences(writer);
    await assertAttachmentsAvailable(writer, { photo_urls: [adopted] });
    await writer.query("INSERT INTO items (home_id, name, photo_urls) VALUES ($1, 'Adopted first', $2)", [home.id, [adopted]]);
    const collection = deleteUnreferenced({ pool, bucket: 'synthetic', keys: [adopted], s3: { send: async () => { deletes++; return {}; } } });
    let waiting = false;
    for (let tries = 0; tries < 100; tries++) {
      waiting = (await pool.query("SELECT 1 FROM pg_locks WHERE locktype = 'advisory' AND classid = 724193 AND NOT granted")).rows.length > 0;
      if (waiting) break;
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    assert.ok(waiting, 'collector waits behind the writer transaction');
    await writer.query('COMMIT');
    assert.equal(await collection, 0);
    assert.equal(deletes, 0, 'committed late references prevent deletion');

    // S3 is deliberately held after the reservation commit. New adoption must
    // already fail, including during a provider timeout/ambiguous outcome.
    let markStarted!: () => void;
    const started = new Promise<void>((resolve) => { markStarted = resolve; });
    let finishS3!: (value: object) => void;
    const pendingS3 = new Promise<object>((resolve) => { finishS3 = resolve; });
    const deleting = deleteUnreferenced({ pool, bucket: 'synthetic', keys: [retired], s3: { send: async () => {
      markStarted();
      return pendingS3;
    } } });
    await started;
    await writer.query('BEGIN');
    await lockAttachmentReferences(writer);
    await assert.rejects(assertAttachmentsAvailable(writer, { photo_urls: [retired] }), /no longer available/);
    await writer.query('ROLLBACK');
    finishS3({ Errors: [{ Code: 'SyntheticFailure' }] });
    await assert.rejects(deleting, /Could not delete 1/);
    assert.equal((await pool.query('SELECT COUNT(*)::int AS count FROM attachment_gc_tombstones WHERE object_key = $1', [retired])).rows[0].count, 1);
    assert.equal(await deleteUnreferenced({ pool, bucket: 'synthetic', keys: [retired], s3: { send: async () => { deletes++; return {}; } } }), 1);
    assert.equal(deletes, 1, 'retry completes the reserved deletion');
    await assert.rejects(assertAttachmentsAvailable(writer, { documents: [{ url: retired }] }), /no longer available/);
    assert.equal((await pool.query('SELECT photo_urls FROM items')).rows[0].photo_urls[0], adopted);
  } finally {
    await writer.query('ROLLBACK');
    writer.release();
  }
});

async function resetDatabase() {
  const target = new URL(process.env.DATABASE_URL!);
  assert.ok(['localhost', '127.0.0.1', '[::1]'].includes(target.hostname)
    && target.pathname.endsWith('_test'), 'Database resets require a local explicitly named _test database');
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
