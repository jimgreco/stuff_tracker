const { DeleteObjectsCommand, ListObjectsV2Command, S3Client } = require('@aws-sdk/client-s3');
const { Pool } = require('pg');
require('dotenv').config();

const bucket = process.env.S3_BUCKET || process.env.AWS_S3_BUCKET;
if (!bucket) throw new Error('S3_BUCKET is required');

const s3 = new S3Client({ region: process.env.S3_REGION || process.env.AWS_REGION || 'us-east-1' });
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.PGSSL === 'true' ? { rejectUnauthorized: false } : false,
});

async function main() {
  const homes = await pool.query('SELECT id FROM homes');
  const existingHomes = new Set(homes.rows.map(({ id }) => id));
  let continuationToken;
  let removed = 0;

  do {
    const page = await s3.send(new ListObjectsV2Command({
      Bucket: bucket,
      Prefix: 'homes/',
      ContinuationToken: continuationToken,
    }));
    const deletedHomeKeys = (page.Contents || []).flatMap(({ Key }) => {
      const homeId = /^homes\/([0-9a-f-]{36})\//i.exec(Key || '')?.[1]?.toLowerCase();
      return homeId && !existingHomes.has(homeId) ? [{ Key }] : [];
    });
    if (deletedHomeKeys.length) {
      const result = await s3.send(new DeleteObjectsCommand({
        Bucket: bucket,
        Delete: { Objects: deletedHomeKeys, Quiet: true },
      }));
      if (result.Errors?.length) {
        throw new Error(`Could not delete ${result.Errors.length} attachments from deleted homes`);
      }
      removed += deletedHomeKeys.length;
    }
    continuationToken = page.NextContinuationToken;
  } while (continuationToken);

  console.log(`Removed ${removed} attachments from deleted homes.`);
}

main().catch((error) => {
  console.error('Deleted-home attachment cleanup failed:', error);
  process.exitCode = 1;
}).finally(() => pool.end());
