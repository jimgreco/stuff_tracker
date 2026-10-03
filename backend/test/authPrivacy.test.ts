import test from 'node:test';
import assert from 'node:assert/strict';
import { OAuth2Client } from 'google-auth-library';
import appleSignin from 'apple-signin-auth';
import { createApp } from '../src/app';
import { pool } from '../src/db/pool';
import { request } from './request';
import { upsertUserWithClient, UserIdentityConflictError } from '../src/lib/users';

process.env.NODE_ENV = 'test';
process.env.APPLE_BUNDLE_ID = 'com.example.synthetic';
process.env.JWT_SECRET = 'synthetic-audit-secret-not-a-production-credential';

test('Google sign-in rejects unverified email before account linking', async (t) => {
  const originalVerify = OAuth2Client.prototype.verifyIdToken;
  const originalConnect = pool.connect;
  const originalError = console.error;
  let databaseCalls = 0;
  let verified: unknown;
  OAuth2Client.prototype.verifyIdToken = (async () => ({
    getPayload: () => ({ sub: 'synthetic-subject', email: 'synthetic@example.test', email_verified: verified }),
  })) as unknown as typeof OAuth2Client.prototype.verifyIdToken;
  pool.connect = (async () => { databaseCalls++; throw new Error('Unexpected account linking'); }) as typeof pool.connect;
  console.error = () => {};
  t.after(() => {
    OAuth2Client.prototype.verifyIdToken = originalVerify;
    pool.connect = originalConnect;
    console.error = originalError;
  });
  const app = createApp();
  for (verified of [false, undefined, 'true']) {
    const response = await request(app, '/auth/google', { method: 'POST', body: { idToken: 'synthetic-credential' } });
    assert.equal(response.status, 401);
    assert.equal(databaseCalls, 0, 'unverified email must never reach identity linking');
  }
  verified = true;
  await request(app, '/auth/google', { method: 'POST', body: { idToken: 'synthetic-credential' } });
  assert.equal(databaseCalls, 1, 'a verified identity still reaches the existing sign-in path');
});

test('provider verification errors do not expose credentials in responses or logs', async (t) => {
  const originalGoogle = OAuth2Client.prototype.verifyIdToken;
  const originalApple = appleSignin.verifyIdToken;
  const originalError = console.error;
  const marker = 'synthetic-private-token-payload';
  const lines: unknown[][] = [];
  OAuth2Client.prototype.verifyIdToken = (async () => { throw new Error(marker); }) as typeof OAuth2Client.prototype.verifyIdToken;
  appleSignin.verifyIdToken = async () => { throw new Error(marker); };
  console.error = (...args: unknown[]) => { lines.push(args); };
  t.after(() => {
    OAuth2Client.prototype.verifyIdToken = originalGoogle;
    appleSignin.verifyIdToken = originalApple;
    console.error = originalError;
  });
  const app = createApp();
  for (const provider of ['google', 'apple']) {
    const response = await request(app, `/auth/${provider}`, {
      method: 'POST', body: { idToken: 'synthetic', identityToken: 'synthetic' },
    });
    assert.equal(response.status, 401);
    assert.ok(!response.text.includes(marker));
  }
  assert.ok(lines.length > 0);
  assert.ok(!lines.flat().map(String).join('\n').includes(marker));
});

test('non-authoritative email cannot link a new provider, while established subjects still work', async () => {
  const existing = { id: 'existing-user', email: 'synthetic@example.test', name: 'Synthetic',
    avatar_url: null, google_id: null, apple_id: 'existing-apple' };
  let updates = 0;
  let knownSubject = false;
  const client = {
    query: async (sql: string) => {
      if (sql.includes('WHERE google_id')) return { rows: knownSubject ? [existing] : [] };
      if (sql.includes('WHERE email')) return { rows: [existing] };
      if (sql.includes('UPDATE users')) { updates++; return { rows: [existing] }; }
      throw new Error('Unexpected fixture query');
    },
  } as Parameters<typeof upsertUserWithClient>[0];
  const identity = { googleId: 'new-google-subject', email: existing.email, name: existing.name,
    allowEmailLinking: false };
  await assert.rejects(upsertUserWithClient(client, identity), UserIdentityConflictError);
  assert.equal(updates, 0);
  knownSubject = true;
  assert.equal((await upsertUserWithClient(client, identity)).id, existing.id);
  assert.equal(updates, 1);
});

test('Google route permits email linking only for authoritative verified addresses', async (t) => {
  const originalVerify = OAuth2Client.prototype.verifyIdToken;
  const originalConnect = pool.connect;
  const originalQuery = pool.query;
  let email = 'synthetic@example.test';
  let hd: string | undefined;
  let updates = 0;
  OAuth2Client.prototype.verifyIdToken = (async () => ({
    getPayload: () => ({ sub: 'new-google-subject', email, email_verified: true, hd }),
  })) as unknown as typeof OAuth2Client.prototype.verifyIdToken;
  pool.connect = (async () => ({
    query: async (sql: string) => {
      const existing = { id: 'existing-user', email, name: 'Synthetic', google_id: null, apple_id: 'existing-apple' };
      if (sql.includes('WHERE google_id')) return { rows: [] };
      if (sql.includes('WHERE email')) return { rows: [existing] };
      if (sql.includes('UPDATE users')) { updates++; return { rows: [existing] }; }
      return { rows: [] };
    }, release() {},
  })) as unknown as typeof pool.connect;
  pool.query = (async () => ({ rows: [{ id: 'synthetic-session', token_id: 'synthetic-token-id' }] })) as typeof pool.query;
  t.after(() => {
    OAuth2Client.prototype.verifyIdToken = originalVerify;
    pool.connect = originalConnect;
    pool.query = originalQuery;
  });
  const app = createApp();
  const login = () => request(app, '/auth/google', { method: 'POST', body: { idToken: 'synthetic' } });
  assert.equal((await login()).status, 409);
  assert.equal(updates, 0);
  email = 'synthetic@gmail.com';
  assert.equal((await login()).status, 200);
  email = 'synthetic@example.test'; hd = 'example.test';
  assert.equal((await login()).status, 200);
  assert.equal(updates, 2);
});
