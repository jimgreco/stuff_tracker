const { DeleteObjectsCommand, ListObjectsV2Command, S3Client } = require('@aws-sdk/client-s3');
const { Pool } = require('pg');
const { referencedAttachmentKeys } = require('./lib/attachment-keys.cjs');

async function cleanupDeletedHomeAttachments({ s3, pool, bucket, minAgeHours = 24, now = Date.now() }) {
  if (!Number.isFinite(minAgeHours) || minAgeHours <= 0) throw new Error('Cleanup minimum age must be positive');
  const cutoff = now - minAgeHours * 60 * 60 * 1000;
  let continuationToken;
  let removed = 0;
  do {
    const page = await s3.send(new ListObjectsV2Command({
      Bucket: bucket, Prefix: 'homes/', ContinuationToken: continuationToken,
    }));
    // Re-read after listing, per page: newly created homes and moved items must
    // be visible before deletion. Missing age data fails closed.
    const homes = await pool.query('SELECT id FROM homes');
    const existingHomes = new Set(homes.rows.map(({ id }) => id));
    const items = await pool.query('SELECT photo_urls, documents FROM items');
    const referenced = referencedAttachmentKeys(items.rows);
    const objects = (page.Contents || []).flatMap(({ Key, LastModified }) => {
      const homeId = /^homes\/([0-9a-f-]{36})\//i.exec(Key || '')?.[1]?.toLowerCase();
      return homeId && !existingHomes.has(homeId) && !referenced.has(Key)
        && LastModified instanceof Date && LastModified.getTime() < cutoff ? [{ Key }] : [];
    });
    if (objects.length) {
      const result = await s3.send(new DeleteObjectsCommand({
        Bucket: bucket, Delete: { Objects: objects, Quiet: true },
      }));
      if (result.Errors?.length) throw new Error(`Could not delete ${result.Errors.length} attachments from deleted homes`);
      removed += objects.length;
    }
    continuationToken = page.NextContinuationToken;
  } while (continuationToken);
  return removed;
}

async function main() {
  require('dotenv').config();
  const bucket = process.env.S3_BUCKET || process.env.AWS_S3_BUCKET;
  if (!bucket) throw new Error('S3_BUCKET is required');
  const s3 = new S3Client({ region: process.env.S3_REGION || process.env.AWS_REGION || 'us-east-1' });
  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: process.env.PGSSL === 'true' ? { rejectUnauthorized: false } : false,
  });
  try {
    const removed = await cleanupDeletedHomeAttachments({ s3, pool, bucket,
      minAgeHours: Number(process.env.ORPHANED_UPLOAD_MIN_AGE_HOURS || 24) });
    console.log(`Removed ${removed} unreferenced attachments from deleted homes.`);
  } finally { await pool.end(); }
}

if (require.main === module) main().catch((error) => {
  console.error('Deleted-home attachment cleanup failed:', error);
  process.exitCode = 1;
});
module.exports = { cleanupDeletedHomeAttachments };
