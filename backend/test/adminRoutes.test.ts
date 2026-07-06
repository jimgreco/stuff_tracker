import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import net from 'node:net';
import { createApp } from '../src/app';
import { pool } from '../src/db/pool';
import { signToken } from '../src/lib/jwt';

process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = process.env.JWT_SECRET ?? 'unit-test-secret-that-is-long-enough';
process.env.GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID ?? 'test-google-client-id';
process.env.APPLE_BUNDLE_ID = process.env.APPLE_BUNDLE_ID ?? 'com.jimgreco.stufftracker';

const originalStuffAdminEmails = process.env.STUFF_ADMIN_EMAILS;
const originalSkipRevocation = process.env.SKIP_TOKEN_REVOCATION_CHECKS;

test.afterEach(() => {
  restoreEnv('STUFF_ADMIN_EMAILS', originalStuffAdminEmails);
  restoreEnv('SKIP_TOKEN_REVOCATION_CHECKS', originalSkipRevocation);
});

test('admin overview requires a signed-in admin email', async (t) => {
  process.env.STUFF_ADMIN_EMAILS = 'admin@example.com';
  process.env.SKIP_TOKEN_REVOCATION_CHECKS = 'true';

  const server = await listen();
  t.after(() => close(server));

  const missing = await fetch(`${serverBaseUrl(server)}/admin/overview`);
  assert.equal(missing.status, 401);

  const nonAdmin = await fetch(`${serverBaseUrl(server)}/admin/overview`, {
    headers: { Authorization: `Bearer ${signToken({ userId: userId(1), email: 'person@example.com' })}` },
  });
  assert.equal(nonAdmin.status, 403);
});

test('admin overview returns account metrics for signed-in admins', async (t) => {
  process.env.STUFF_ADMIN_EMAILS = 'admin@example.com';
  process.env.SKIP_TOKEN_REVOCATION_CHECKS = 'true';

  const originalQuery = pool.query.bind(pool);
  pool.query = (async (query: unknown) => {
    const sql = String(query);
    if (sql.includes('(SELECT COUNT(*) FROM users)')) {
      return {
        rows: [{
          users: '2',
          homes: '3',
          locations: '4',
          items: '5',
          active_entitlements: '1',
          active_sessions: '6',
        }],
      };
    }
    if (sql.includes('FROM users u')) {
      return {
        rows: [{
          id: userId(1),
          email: 'admin@example.com',
          name: 'Admin Person',
          created_at: '2026-07-05T12:00:00.000Z',
          updated_at: '2026-07-05T12:05:00.000Z',
          home_count: '2',
          shared_home_count: '1',
          item_count: '9',
          active_session_count: '1',
          last_seen_at: '2026-07-05T12:10:00.000Z',
          active_entitlement_source: 'admin',
          active_entitlement_expires_at: null,
        }],
      };
    }
    return originalQuery(query as never);
  }) as typeof pool.query;

  const server = await listen();
  t.after(() => {
    pool.query = originalQuery;
    return close(server);
  });

  const response = await fetch(`${serverBaseUrl(server)}/admin/overview`, {
    headers: { Authorization: `Bearer ${signToken({ userId: userId(1), email: 'admin@example.com' })}` },
  });
  const body = await response.json() as {
    current_user: { email: string };
    totals: { users: number; active_sessions: number };
    users: Array<{ email: string; home_count: number; active_entitlement_source: string }>;
  };

  assert.equal(response.status, 200);
  assert.equal(body.current_user.email, 'admin@example.com');
  assert.equal(body.totals.users, 2);
  assert.equal(body.totals.active_sessions, 6);
  assert.equal(body.users[0].email, 'admin@example.com');
  assert.equal(body.users[0].home_count, 2);
  assert.equal(body.users[0].active_entitlement_source, 'admin');
});

test('signed-in admins can set users manually paid and back to free', async (t) => {
  process.env.STUFF_ADMIN_EMAILS = 'admin@example.com';
  process.env.SKIP_TOKEN_REVOCATION_CHECKS = 'true';

  const targetUserId = userId(2);
  const planEntitlements = [
    [{ source: 'manual', product_id: null, expires_at: null, app_store_environment: null }],
    [],
  ];
  let revokeCount = 0;
  const originalQuery = pool.query.bind(pool);
  pool.query = (async (query: unknown) => {
    const sql = String(query);
    if (sql.includes('SELECT id, email, name FROM users WHERE id = $1')) {
      return {
        rows: [{
          id: targetUserId,
          email: 'person@example.com',
          name: 'Person',
        }],
      };
    }
    if (sql.includes('UPDATE user_entitlements')) {
      revokeCount += 1;
      return { rows: [], rowCount: 1 };
    }
    if (sql.includes('INSERT INTO user_entitlements')) {
      return {
        rows: [{
          id: userId(3),
          user_id: targetUserId,
          source: 'manual',
          status: 'active',
          expires_at: null,
        }],
      };
    }
    if (sql.includes('SELECT source, product_id, expires_at, app_store_environment')) {
      return { rows: planEntitlements.shift() ?? [] };
    }
    if (sql.includes('FROM locations l') && sql.includes('FROM items i')) {
      return {
        rows: [{
          containers: '0',
          items: '0',
          images: '0',
          documents: '0',
        }],
      };
    }
    return originalQuery(query as never);
  }) as typeof pool.query;

  const server = await listen();
  t.after(() => {
    pool.query = originalQuery;
    return close(server);
  });

  const headers = { Authorization: `Bearer ${signToken({ userId: userId(1), email: 'admin@example.com' })}` };
  const paidResponse = await fetch(`${serverBaseUrl(server)}/admin/users/${targetUserId}/manual-entitlement`, {
    method: 'POST',
    headers,
  });
  const paidBody = await paidResponse.json() as {
    entitlement: { source: string };
    plan: { tier: string; entitlement: { source: string } | null };
  };

  assert.equal(paidResponse.status, 201);
  assert.equal(paidBody.entitlement.source, 'manual');
  assert.equal(paidBody.plan.tier, 'paid');
  assert.equal(paidBody.plan.entitlement?.source, 'manual');

  const freeResponse = await fetch(`${serverBaseUrl(server)}/admin/users/${targetUserId}/manual-entitlement`, {
    method: 'DELETE',
    headers,
  });
  const freeBody = await freeResponse.json() as {
    revoked_count: number;
    plan: { tier: string; entitlement: unknown };
  };

  assert.equal(freeResponse.status, 200);
  assert.equal(freeBody.revoked_count, 1);
  assert.equal(freeBody.plan.tier, 'free');
  assert.equal(freeBody.plan.entitlement, null);
  assert.equal(revokeCount, 2);
});

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

function restoreEnv(key: string, value: string | undefined): void {
  if (value === undefined) {
    delete process.env[key];
    return;
  }

  process.env[key] = value;
}

function userId(index: number): string {
  return `00000000-0000-4000-8000-${String(index).padStart(12, '0')}`;
}
