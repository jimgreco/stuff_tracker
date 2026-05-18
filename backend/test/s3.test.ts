import test from 'node:test';
import assert from 'node:assert/strict';
import { attachmentKeyFromUrl, maxUploadBytes } from '../src/lib/s3';

process.env.S3_BUCKET = 'stuff-test-bucket';
process.env.S3_REGION = 'us-east-2';
process.env.S3_PUBLIC_BASE_URL = 'https://cdn.example.com/uploads';
process.env.MAX_PHOTO_UPLOAD_BYTES = '1234';
process.env.MAX_DOCUMENT_UPLOAD_BYTES = '5678';

test('attachment key parser accepts stable S3, CDN, signed, and raw key values', () => {
  const key = 'homes/home-1/items/photos/file name.jpg';
  const encoded = 'homes/home-1/items/photos/file%20name.jpg';

  assert.equal(attachmentKeyFromUrl(key), key);
  assert.equal(attachmentKeyFromUrl(`https://cdn.example.com/uploads/${encoded}`), key);
  assert.equal(attachmentKeyFromUrl(`https://stuff-test-bucket.s3.us-east-2.amazonaws.com/${encoded}`), key);
  assert.equal(attachmentKeyFromUrl(`https://stuff-test-bucket.s3.us-east-2.amazonaws.com/${encoded}?X-Amz-Signature=abc`), key);
  assert.equal(attachmentKeyFromUrl('https://example.com/not-ours.jpg'), undefined);
});

test('upload size limits are configurable per attachment kind', () => {
  assert.equal(maxUploadBytes('photo'), 1234);
  assert.equal(maxUploadBytes('document'), 5678);
});
