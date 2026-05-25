import test from 'node:test';
import assert from 'node:assert/strict';
import {
  assertAllowedAttachmentBytes,
  attachmentKeyFromUrl,
  maxUploadBytes,
  requiredUploadHeaders,
  S3ConfigurationError,
  UploadValidationError,
} from '../src/lib/s3';

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

test('upload headers require server-side encryption by default', () => {
  const previous = process.env.S3_UPLOAD_SERVER_SIDE_ENCRYPTION;
  delete process.env.S3_UPLOAD_SERVER_SIDE_ENCRYPTION;

  try {
    assert.deepEqual(requiredUploadHeaders('image/jpeg'), {
      'Content-Type': 'image/jpeg',
      'x-amz-server-side-encryption': 'AES256',
    });
  } finally {
    restoreEnv('S3_UPLOAD_SERVER_SIDE_ENCRYPTION', previous);
  }
});

test('upload encryption can use KMS or be explicitly disabled', () => {
  const previousEncryption = process.env.S3_UPLOAD_SERVER_SIDE_ENCRYPTION;
  const previousKmsKey = process.env.S3_UPLOAD_KMS_KEY_ID;

  try {
    process.env.S3_UPLOAD_SERVER_SIDE_ENCRYPTION = 'aws:kms';
    process.env.S3_UPLOAD_KMS_KEY_ID = 'alias/stuff-uploads';
    assert.deepEqual(requiredUploadHeaders('application/pdf'), {
      'Content-Type': 'application/pdf',
      'x-amz-server-side-encryption': 'aws:kms',
      'x-amz-server-side-encryption-aws-kms-key-id': 'alias/stuff-uploads',
    });

    process.env.S3_UPLOAD_SERVER_SIDE_ENCRYPTION = 'none';
    assert.deepEqual(requiredUploadHeaders('application/pdf'), {
      'Content-Type': 'application/pdf',
    });
  } finally {
    restoreEnv('S3_UPLOAD_SERVER_SIDE_ENCRYPTION', previousEncryption);
    restoreEnv('S3_UPLOAD_KMS_KEY_ID', previousKmsKey);
  }
});

test('upload encryption rejects unsupported algorithms', () => {
  const previous = process.env.S3_UPLOAD_SERVER_SIDE_ENCRYPTION;
  process.env.S3_UPLOAD_SERVER_SIDE_ENCRYPTION = 'DES';

  try {
    assert.throws(() => requiredUploadHeaders('image/jpeg'), S3ConfigurationError);
  } finally {
    restoreEnv('S3_UPLOAD_SERVER_SIDE_ENCRYPTION', previous);
  }
});

test('attachment byte validation accepts supported photos and documents', () => {
  assert.doesNotThrow(() => assertAllowedAttachmentBytes('photo', 'image/jpeg', bytes([
    0xff, 0xd8, 0xff, 0xe0,
  ])));
  assert.doesNotThrow(() => assertAllowedAttachmentBytes('photo', 'image/png', bytes([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
  ])));
  assert.doesNotThrow(() => assertAllowedAttachmentBytes('document', 'application/pdf', ascii('%PDF-1.7')));
  assert.doesNotThrow(() => assertAllowedAttachmentBytes('document', 'application/zip', bytes([
    0x50, 0x4b, 0x03, 0x04,
  ])));
  assert.doesNotThrow(() => assertAllowedAttachmentBytes('document', 'text/plain', ascii('plain text')));
});

test('attachment byte validation rejects mismatched upload content', () => {
  assert.throws(
    () => assertAllowedAttachmentBytes('photo', 'image/jpeg', ascii('%PDF-1.7')),
    UploadValidationError
  );
  assert.throws(
    () => assertAllowedAttachmentBytes('document', 'application/pdf', bytes([0xff, 0xd8, 0xff, 0xe0])),
    UploadValidationError
  );
});

function bytes(values: number[]): Uint8Array {
  return Uint8Array.from(values);
}

function ascii(value: string): Uint8Array {
  return Buffer.from(value, 'ascii');
}

function restoreEnv(name: string, value: string | undefined): void {
  if (value === undefined) {
    delete process.env[name];
    return;
  }

  process.env[name] = value;
}
