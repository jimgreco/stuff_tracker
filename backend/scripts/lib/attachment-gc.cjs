const { DeleteObjectsCommand } = require('@aws-sdk/client-s3');
const { referencedAttachmentKeys } = require('./attachment-keys.cjs');

// Same lock is acquired by every application inventory transaction. READ COMMITTED
// reads after acquiring it observe the preceding writer's committed references.
const ATTACHMENT_LOCK = 'SELECT pg_advisory_xact_lock(724193, 1)';

class AttachmentRetiredError extends Error {
  constructor() {
    super('An attachment is no longer available. Upload it again before saving.');
    this.name = 'AttachmentRetiredError';
  }
}

async function lockAttachmentReferences(client) {
  await client.query(ATTACHMENT_LOCK);
}

async function assertAttachmentsAvailable(client, attachments) {
  const keys = [...referencedAttachmentKeys([attachments])];
  if (!keys.length) return;
  const result = await client.query(
    'SELECT object_key FROM attachment_gc_tombstones WHERE object_key = ANY($1::text[]) LIMIT 1', [keys]
  );
  if (result.rows.length) throw new AttachmentRetiredError();
}

async function reserveUnreferenced(pool, keys, { onlyDeletedHomes = false } = {}) {
  if (!keys.length) return [];
  const client = await pool.connect();
  try {
    await client.query('BEGIN ISOLATION LEVEL READ COMMITTED');
    await lockAttachmentReferences(client);
    const referenced = referencedAttachmentKeys((await client.query('SELECT photo_urls, documents FROM items')).rows);
    const homes = onlyDeletedHomes
      ? new Set((await client.query('SELECT id FROM homes')).rows.map(({ id }) => id.toLowerCase())) : null;
    const reserved = [...new Set(keys)].filter((key) => {
      const homeID = /^homes\/([0-9a-f-]{36})\//i.exec(key)?.[1]?.toLowerCase();
      return homeID && !referenced.has(key) && (!homes || !homes.has(homeID));
    });
    if (reserved.length) {
      await client.query(`INSERT INTO attachment_gc_tombstones (object_key)
        SELECT unnest($1::text[]) ON CONFLICT (object_key) DO NOTHING`, [reserved]);
    }
    await client.query('COMMIT');
    return reserved;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally { client.release(); }
}

async function deleteUnreferenced({ pool, s3, bucket, keys, onlyDeletedHomes = false }) {
  let removed = 0;
  for (let offset = 0; offset < keys.length; offset += 1000) {
    // Commit the irreversible reservation BEFORE S3. A timeout, process crash, DB
    // outage or partial S3 failure must never allow a deleted key to be re-adopted.
    const reserved = await reserveUnreferenced(pool, keys.slice(offset, offset + 1000), { onlyDeletedHomes });
    if (!reserved.length) continue;
    const result = await s3.send(new DeleteObjectsCommand({
      Bucket: bucket, Delete: { Objects: reserved.map((Key) => ({ Key })), Quiet: true },
    }));
    if (result.Errors?.length) throw new Error(`Could not delete ${result.Errors.length} reserved attachments`);
    await pool.query('UPDATE attachment_gc_tombstones SET deleted_at = NOW() WHERE object_key = ANY($1::text[])', [reserved]);
    removed += reserved.length;
  }
  return removed;
}

module.exports = { ATTACHMENT_LOCK, AttachmentRetiredError, lockAttachmentReferences, assertAttachmentsAvailable,
  reserveUnreferenced, deleteUnreferenced };
