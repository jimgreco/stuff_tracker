import test from 'node:test';
import assert from 'node:assert/strict';
import { S3Client } from '@aws-sdk/client-s3';
import { createApp } from '../src/app';
import { pool } from '../src/db/pool';
import { signToken } from '../src/lib/jwt';
import { request } from './request';

process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'synthetic-audit-secret-not-a-production-credential';
process.env.S3_BUCKET = 'audit-synthetic-bucket';
process.env.S3_REGION = 'us-east-1';
process.env.AWS_ACCESS_KEY_ID = 'synthetic-test-key';
process.env.AWS_SECRET_ACCESS_KEY = 'synthetic-test-secret';
process.env.AWS_EC2_METADATA_DISABLED = 'true';
delete process.env.S3_PUBLIC_BASE_URL;

const home = '11111111-1111-4111-8111-111111111111';
const foreign = '22222222-2222-4222-8222-222222222222';
const source = '33333333-3333-4333-8333-333333333333';
const itemId = '44444444-4444-4444-8444-444444444444';
const url = (homeId: string, file = 'photo.jpg') =>
  `https://audit-synthetic-bucket.s3.amazonaws.com/homes/${homeId}/items/photos/${file}`;

test('item writes cannot turn another home attachment URL into a fresh read grant', async (t) => {
  const originalIntegrationMode = process.env.RUN_DATABASE_INTEGRATION_TESTS;
  process.env.RUN_DATABASE_INTEGRATION_TESTS = 'true';
  const originalQuery = pool.query;
  const originalConnect = pool.connect;
  const originalSend = S3Client.prototype.send;
  let storedHome = home;
  let storedPhotos: string[] = [];
  let s3Reads = 0;
  let writes = 0;
  let retired = false;
  let locked = false;
  pool.query = (async (sql: string, values: unknown[] = []) => {
    if (sql === 'SELECT tokens_revoked_before FROM users WHERE id = $1') {
      assert.equal(values[0], 'synthetic-owner');
      return { rows: [{ tokens_revoked_before: null }] };
    }
    if (sql.includes('SELECT home_id, photo_urls, documents FROM items')) {
      return { rows: [{ home_id: storedHome, photo_urls: storedPhotos, documents: [] }] };
    }
    if (sql.includes('SELECT id FROM homes')) {
      return { rows: values[0] === foreign ? [] : [{ id: values[0] }] };
    }
    if (sql.includes('FROM home_members')) return { rows: [] };
    if (sql.includes('SELECT owner_id')) return { rows: [{ owner_id: 'synthetic-owner' }] };
    if (sql.includes('FROM user_entitlements')) return { rows: [{ source: 'manual', expires_at: null }] };
    if (sql.includes('COALESCE')) return { rows: [{}] };
    throw new Error('Unexpected fixture query');
  }) as typeof pool.query;
  pool.connect = (async () => ({
    query: async (sql: string) => {
      if (sql.startsWith('BEGIN')) locked = false;
      if (sql.includes('pg_advisory_xact_lock')) locked = true;
      if (sql.includes('FROM attachment_gc_tombstones')) {
        assert.ok(locked);
        return { rows: retired ? [{ object_key: 'synthetic-retired-key' }] : [] };
      }
      if (sql.includes('INSERT INTO items') || sql.includes('UPDATE items')) {
        writes++;
        return { rows: [{ id: itemId, home_id: home, photo_urls: storedPhotos, documents: [] }] };
      }
      return { rows: [] };
    },
    release() {},
  })) as unknown as typeof pool.connect;
  S3Client.prototype.send = (async () => {
    s3Reads++;
    return { Body: Uint8Array.from([0xff, 0xd8, 0xff, 0xe0]) };
  }) as typeof S3Client.prototype.send;

  const app = createApp();
  t.after(() => {
    if (originalIntegrationMode === undefined) delete process.env.RUN_DATABASE_INTEGRATION_TESTS;
    else process.env.RUN_DATABASE_INTEGRATION_TESTS = originalIntegrationMode;
    pool.query = originalQuery;
    pool.connect = originalConnect;
    S3Client.prototype.send = originalSend;
  });
  const base = `/homes/${home}/items`;
  const token = signToken({ userId: 'synthetic-owner', email: 'audit@example.test' });
  async function write(method: string, body: object) {
    return request(app, base + (method === 'PATCH' ? `/${itemId}` : ''), {
      method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body,
    });
  }

  for (const method of ['POST', 'PATCH']) {
    for (const attachment of [
      { photo_urls: [url(foreign) + '?X-Amz-Expires=1&X-Amz-Signature=expired'] },
      { documents: [{ id: 'foreign-document', name: 'foreign.jpg', url: url(foreign), content_type: 'image/jpeg' }] },
    ]) {
      const response = await write(method, { name: 'Synthetic item', ...attachment });
      assert.equal(response.status, 400, `${method} must reject a foreign attachment`);
    }
  }
  assert.equal(s3Reads, 0, 'authorization happens before reading private bytes');
  assert.equal(writes, 0, 'rejected attachments are never persisted');

  let response = await write('POST', { name: 'Synthetic item', photo_urls: [url(home)] });
  assert.equal(response.status, 201);

  // An authorized move retains existing source-home files. Future edits retain
  // exactly those files, but do not authorize other files from the old home.
  storedHome = source;
  storedPhotos = [url(source)];
  response = await write('PATCH', { home_id: home, photo_urls: [url(source)] });
  assert.equal(response.status, 200);
  storedHome = home;
  response = await write('PATCH', { photo_urls: [url(source) + '?X-Amz-Signature=renewed'] });
  assert.equal(response.status, 200);
  response = await write('PATCH', { photo_urls: [url(source, 'unrelated.jpg')] });
  assert.equal(response.status, 400);

  retired = true;
  const writesBeforeReservation = writes;
  for (const method of ['POST', 'PATCH']) {
    response = await write(method, { name: 'Late save', photo_urls: [url(home)] });
    assert.equal(response.status, 409);
    assert.equal(JSON.parse(response.text).code, 'attachment_retired');
  }
  assert.equal(writes, writesBeforeReservation);
});
