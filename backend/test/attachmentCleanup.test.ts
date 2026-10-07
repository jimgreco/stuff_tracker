import test from 'node:test';
import assert from 'node:assert/strict';
import { S3Client, ListObjectsV2Command, DeleteObjectsCommand } from '@aws-sdk/client-s3';
import { pool } from '../src/db/pool';
import { deleteHomeAttachments } from '../src/lib/s3';

const { cleanupDeletedHomeAttachments } = require('../scripts/cleanup-deleted-home-attachments.cjs');
const { cleanupOrphanedUploads } = require('../scripts/cleanup-orphaned-uploads.cjs');
const { deleteUnreferenced, assertAttachmentsAvailable } = require('../scripts/lib/attachment-gc.cjs');
const { referencedAttachmentKeys } = require('../scripts/lib/attachment-keys.cjs');
process.env.S3_BUCKET = 'audit-synthetic-bucket';
delete process.env.S3_PUBLIC_BASE_URL;
const oldHome = '11111111-1111-4111-8111-111111111111';
const liveHome = '22222222-2222-4222-8222-222222222222';
const photo = `homes/${oldHome}/items/photos/moved image.jpg`;
const document = `homes/${oldHome}/items/documents/moved.pdf`;
const abandoned = `homes/${oldHome}/items/photos/abandoned.jpg`;
const url = (key: string) => `https://audit-synthetic-bucket.s3.amazonaws.com/${key.replaceAll(' ', '%20')}?X-Amz-Signature=expired`;
const survivingItems = [{ photo_urls: [url(photo)], documents: [{ url: url(document) }] }];

// A transaction-capable synthetic database; never connects to a real endpoint.
function transactional(db: { query: (sql: string, values?: unknown[]) => Promise<any> }) {
  return { ...db, connect: async () => ({
    query: async (sql: string, values?: unknown[]) => {
      if (sql === 'SELECT photo_urls, documents FROM items' || sql === 'SELECT id FROM homes') return db.query(sql, values);
      return { rows: [] };
    },
    release() {},
  }) };
}

test('account deletion preserves exact moved photo/document references across S3 pages', async (t) => {
  const originalQuery = pool.query;
  const originalConnect = pool.connect;
  const originalSend = S3Client.prototype.send;
  pool.query = (async (sql: string) => ({ rows: sql === 'SELECT id FROM homes' ? [{ id: liveHome }] : survivingItems })) as typeof pool.query;
  pool.connect = transactional({ query: (sql) => (pool.query as any)(sql) }).connect as any;
  let pages = 0;
  const deleted: string[] = [];
  S3Client.prototype.send = (async (command: any) => {
    if (command instanceof ListObjectsV2Command) {
      pages++;
      assert.equal(command.input.Prefix, `homes/${oldHome}/`);
      return pages === 1 ? { Contents: [{ Key: photo }, { Key: abandoned }], NextContinuationToken: 'next' }
        : { Contents: [{ Key: document }] };
    }
    assert.ok(command instanceof DeleteObjectsCommand);
    deleted.push(...command.input.Delete.Objects.map((object: any) => object.Key));
    return {};
  }) as typeof S3Client.prototype.send;
  t.after(() => { pool.query = originalQuery; pool.connect = originalConnect; S3Client.prototype.send = originalSend; });
  await deleteHomeAttachments([oldHome]);
  assert.equal(pages, 2);
  assert.deepEqual(deleted, [abandoned]);
});

test('cleanup shares all supported reference formats and fails closed on malformed keys', () => {
  const references = referencedAttachmentKeys([{ photo_urls: [url(photo)], documents: [{ id: document, url: 'https://external.example/manual.pdf' }] }]);
  assert.deepEqual([...references].sort(), [photo, document].sort());
  assert.throws(() => referencedAttachmentKeys([{ photo_urls: ['https://audit-synthetic-bucket.s3.amazonaws.com/%malformed'] }]));
});

test('deleted-home sweep retains moved files, live homes, fresh uploads and unknown ages', async () => {
  const now = Date.UTC(2026, 9, 3);
  const old = new Date(now - 48 * 3600000);
  const deleted: string[] = [];
  let listed = false;
  const fakePool = { query: async (sql: string) => {
    assert.equal(listed, true, 'read current references after listing');
    return { rows: sql === 'SELECT id FROM homes' ? [{ id: liveHome }] : survivingItems };
  } };
  const fakeS3 = { send: async (command: any) => {
    if (command instanceof ListObjectsV2Command) {
      listed = true;
      return { Contents: [
        { Key: photo, LastModified: old }, { Key: document, LastModified: old },
        { Key: abandoned, LastModified: old },
        { Key: `homes/${oldHome}/items/photos/fresh.jpg`, LastModified: new Date(now) },
        { Key: `homes/${oldHome}/items/photos/unknown.jpg` },
        { Key: `homes/${liveHome}/items/photos/live.jpg`, LastModified: old },
      ] };
    }
    deleted.push(...command.input.Delete.Objects.map((object: any) => object.Key));
    return {};
  } };
  assert.equal(await cleanupDeletedHomeAttachments({ pool: transactional(fakePool), s3: fakeS3, bucket: 'synthetic', now }), 1);
  assert.deepEqual(deleted, [abandoned]);
});

test('deleted-home cleanup surfaces partial S3 failures and rejects unsafe grace periods', async () => {
  const pool = { query: async () => ({ rows: [] }) };
  const s3 = { send: async (command: any) => command instanceof ListObjectsV2Command
    ? { Contents: [{ Key: abandoned, LastModified: new Date(0) }] }
    : { Errors: [{ Code: 'AccessDenied' }] } };
  await assert.rejects(cleanupDeletedHomeAttachments({ pool: transactional(pool), s3, bucket: 'synthetic' }), /Could not delete 1/);
  for (const minAgeHours of [0, -1, NaN]) {
    await assert.rejects(cleanupDeletedHomeAttachments({ pool: transactional(pool), s3, bucket: 'synthetic', minAgeHours }), /minimum age/);
  }
});

test('account cleanup does not touch S3 if reference lookup fails', async (t) => {
  const originalQuery = pool.query;
  const originalSend = S3Client.prototype.send;
  pool.query = (async () => { throw new Error('Synthetic database outage'); }) as typeof pool.query;
  let calls = 0;
  S3Client.prototype.send = (async () => { calls++; return {}; }) as typeof S3Client.prototype.send;
  t.after(() => { pool.query = originalQuery; S3Client.prototype.send = originalSend; });
  await assert.rejects(deleteHomeAttachments([oldHome]), /database outage/);
  assert.equal(calls, 0);
});

test('orphan cleanup rechecks late references, stays dry by default, and reports partial failures', async () => {
  let reads = 0;
  const deleted: string[] = [];
  const pool = { query: async () => ({ rows: ++reads === 1 ? [] : survivingItems }) };
  let failDelete = false;
  const s3 = { send: async (command: any) => {
    if (command instanceof ListObjectsV2Command) {
      return { Contents: [photo, abandoned].map((Key) => ({ Key, LastModified: new Date(0) })) };
    }
    deleted.push(...command.input.Delete.Objects.map((object: any) => object.Key));
    return failDelete ? { Errors: [{ Code: 'AccessDenied' }] } : {};
  } };
  assert.deepEqual(await cleanupOrphanedUploads({ pool: transactional(pool), s3, bucket: 'synthetic' }), { candidates: 2, removed: 0 });
  assert.deepEqual(deleted, []);
  reads = 0;
  assert.deepEqual(await cleanupOrphanedUploads({ pool: transactional(pool), s3, bucket: 'synthetic', dryRun: false }), { candidates: 2, removed: 1 });
  assert.deepEqual(deleted, [abandoned]);
  failDelete = true;
  await assert.rejects(cleanupOrphanedUploads({ pool: transactional(pool), s3, bucket: 'synthetic', dryRun: false }), /Could not delete 1/);
});


test('reservation is committed before S3 and remains unadoptable after timeout or partial deletion', async () => {
  for (const failure of ['timeout', 'partial', 'none']) {
    const retired = new Set<string>();
    let pending: string[] = [];
    let committed = false;
    let released = false;
    const db = {
      query: async () => ({ rows: [] }),
      connect: async () => ({
        query: async (sql: string, values?: string[][]) => {
          if (sql.includes('INSERT INTO attachment_gc_tombstones')) pending = values![0];
          if (sql === 'COMMIT') { for (const key of pending) retired.add(key); committed = true; }
          return { rows: [] };
        },
        release() { released = true; },
      }),
    };
    const s3 = { send: async () => {
      assert.ok(committed && released, 'do not hold the DB transaction/lock over S3');
      await assert.rejects(assertAttachmentsAvailable({ query: async (_sql: string, values: string[][]) => ({
        rows: values[0].filter((key) => retired.has(key)).map((object_key) => ({ object_key })),
      }) }, { photo_urls: [url(abandoned)] }), /no longer available/);
      if (failure === 'timeout') throw new Error('Synthetic timeout with unknown S3 outcome');
      return failure === 'partial' ? { Errors: [{ Code: 'AccessDenied' }] } : {};
    } };
    const deletion = deleteUnreferenced({ pool: db, s3, bucket: 'synthetic', keys: [abandoned] });
    if (failure === 'none') assert.equal(await deletion, 1);
    else await assert.rejects(deletion, /timeout|Could not delete/);
    assert.ok(retired.has(abandoned), 'never roll back a reservation after asking S3 to delete');
  }
});

test('failed reservation commit never sends S3 deletes and releases the connection', async () => {
  let rolledBack = false;
  let released = false;
  let calls = 0;
  const db = { connect: async () => ({
    query: async (sql: string) => {
      if (sql === 'COMMIT') throw new Error('Synthetic commit failure');
      if (sql === 'ROLLBACK') rolledBack = true;
      return { rows: [] };
    },
    release() { released = true; },
  }) };
  await assert.rejects(deleteUnreferenced({ pool: db, s3: { send: async () => { calls++; } }, bucket: 'synthetic', keys: [abandoned] }), /commit failure/);
  assert.equal(calls, 0);
  assert.ok(rolledBack && released);
});
