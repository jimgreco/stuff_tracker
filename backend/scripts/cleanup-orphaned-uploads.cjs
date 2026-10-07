const { ListObjectsV2Command, S3Client } = require('@aws-sdk/client-s3');
const { Pool } = require('pg');
const { deleteUnreferenced } = require('./lib/attachment-gc.cjs');
const { referencedAttachmentKeys } = require('./lib/attachment-keys.cjs');

async function cleanupOrphanedUploads({ s3, pool, bucket, dryRun = true, minAgeHours = 24, now = Date.now() }) {
  if (!Number.isFinite(minAgeHours) || minAgeHours <= 0) throw new Error('Cleanup minimum age must be positive');
  const cutoff = now - minAgeHours * 60 * 60 * 1000;
  const readReferences = async () => referencedAttachmentKeys((await pool.query('SELECT photo_urls, documents FROM items')).rows);
  const referenced = await readReferences();
  const orphaned = [];
  let ContinuationToken;
  do {
    const page = await s3.send(new ListObjectsV2Command({ Bucket: bucket, Prefix: 'homes/', ContinuationToken }));
    for (const object of page.Contents || []) {
      const modified = object.LastModified?.getTime();
      if (object.Key && !referenced.has(object.Key) && Number.isFinite(modified) && modified < cutoff) orphaned.push(object.Key);
    }
    ContinuationToken = page.NextContinuationToken;
  } while (ContinuationToken);
  if (dryRun) return { candidates: orphaned.length, removed: 0 };

  const removed = await deleteUnreferenced({ pool, s3, bucket, keys: orphaned });
  return { candidates: orphaned.length, removed };
}

async function main() {
  require('dotenv').config();
  const bucket = process.env.S3_BUCKET || process.env.AWS_S3_BUCKET;
  if (!bucket) throw new Error('S3_BUCKET is required');
  if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL is required');
  const dryRun = process.env.DELETE_ORPHANED_UPLOADS !== 'true';
  const s3 = new S3Client({ region: process.env.S3_REGION || process.env.AWS_REGION || 'us-east-1' });
  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: process.env.PGSSL === 'true' ? { rejectUnauthorized: false } : undefined,
  });
  try {
    const result = await cleanupOrphanedUploads({ s3, pool, bucket, dryRun,
      minAgeHours: Number(process.env.ORPHANED_UPLOAD_MIN_AGE_HOURS || 24) });
    console.log(dryRun ? `Dry run: ${result.candidates} orphaned uploads would be deleted` : `Deleted ${result.removed} orphaned uploads`);
  } finally { await pool.end(); }
}

if (require.main === module) main().catch((error) => {
  console.error('Orphaned attachment cleanup failed:', error);
  process.exitCode = 1;
});
module.exports = { cleanupOrphanedUploads };
