const { DeleteObjectsCommand, ListObjectsV2Command, S3Client } = require('@aws-sdk/client-s3');
const { Pool } = require('pg');

require('dotenv').config();

const bucket = process.env.S3_BUCKET || process.env.AWS_S3_BUCKET;
if (!bucket) {
  console.error('S3_BUCKET is required');
  process.exit(1);
}

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  console.error('DATABASE_URL is required');
  process.exit(1);
}

const region = process.env.S3_REGION || process.env.AWS_REGION || 'us-east-1';
const dryRun = process.env.DELETE_ORPHANED_UPLOADS !== 'true';
const minAgeHours = Number(process.env.ORPHANED_UPLOAD_MIN_AGE_HOURS || 24);
const cutoff = Date.now() - minAgeHours * 60 * 60 * 1000;
const s3 = new S3Client({ region });

async function main() {
  const referenced = await referencedAttachmentKeys();
  const orphaned = [];

  let ContinuationToken;
  do {
    const page = await s3.send(new ListObjectsV2Command({
      Bucket: bucket,
      Prefix: 'homes/',
      ContinuationToken,
    }));

    for (const object of page.Contents || []) {
      if (!object.Key || referenced.has(object.Key)) {
        continue;
      }

      const lastModified = object.LastModified?.getTime() ?? 0;
      if (lastModified > cutoff) {
        continue;
      }

      orphaned.push(object.Key);
    }

    ContinuationToken = page.NextContinuationToken;
  } while (ContinuationToken);

  if (dryRun) {
    console.log(`Dry run: ${orphaned.length} orphaned uploads would be deleted`);
    orphaned.slice(0, 50).forEach((key) => console.log(key));
    return;
  }

  for (let i = 0; i < orphaned.length; i += 1000) {
    const batch = orphaned.slice(i, i + 1000);
    await s3.send(new DeleteObjectsCommand({
      Bucket: bucket,
      Delete: {
        Objects: batch.map((Key) => ({ Key })),
        Quiet: true,
      },
    }));
  }

  console.log(`Deleted ${orphaned.length} orphaned uploads`);
}

async function referencedAttachmentKeys() {
  const pool = new Pool({
    connectionString: databaseUrl,
    ssl: process.env.PGSSL === 'true' ? { rejectUnauthorized: false } : undefined,
  });

  try {
    const { rows } = await pool.query('SELECT photo_urls, documents FROM items');
    const keys = new Set();

    for (const row of rows) {
      for (const url of row.photo_urls || []) {
        addKey(keys, url);
      }
      for (const document of row.documents || []) {
        addKey(keys, document?.url);
        addKey(keys, document?.id);
      }
    }

    return keys;
  } finally {
    await pool.end();
  }
}

function addKey(keys, value) {
  const key = attachmentKeyFromValue(value);
  if (key) {
    keys.add(key);
  }
}

function attachmentKeyFromValue(value) {
  if (typeof value !== 'string' || !value) {
    return undefined;
  }

  if (value.startsWith('homes/')) {
    return value;
  }

  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    return undefined;
  }

  const configuredBase = process.env.S3_PUBLIC_BASE_URL?.replace(/\/+$/, '');
  if (configuredBase && value.startsWith(`${configuredBase}/`)) {
    return decodeKeyPath(value.slice(configuredBase.length + 1).split('?')[0]);
  }

  if (parsed.hostname === `${bucket}.s3.amazonaws.com` || parsed.hostname.startsWith(`${bucket}.s3.`)) {
    return decodeKeyPath(parsed.pathname.replace(/^\/+/, ''));
  }

  return undefined;
}

function decodeKeyPath(keyPath) {
  return keyPath.split('/').map(decodeURIComponent).join('/');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
