import { randomUUID } from 'crypto';
import { PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

export type ItemUploadKind = 'photo' | 'document';

export class S3ConfigurationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'S3ConfigurationError';
  }
}

interface UploadRequest {
  homeId: string;
  kind: ItemUploadKind;
  fileName: string;
  contentType: string;
}

interface UploadResponse {
  uploadUrl: string;
  fileUrl: string;
  key: string;
  headers: Record<string, string>;
}

let s3Client: S3Client | undefined;

function s3Region(): string {
  return process.env.S3_REGION || process.env.AWS_REGION || 'us-east-1';
}

function s3Bucket(): string {
  const bucket = process.env.S3_BUCKET || process.env.AWS_S3_BUCKET;
  if (!bucket) {
    throw new S3ConfigurationError('S3_BUCKET is required to create item attachment uploads');
  }
  return bucket;
}

function client(): S3Client {
  if (!s3Client) {
    s3Client = new S3Client({ region: s3Region() });
  }
  return s3Client;
}

function safeFileName(fileName: string, kind: ItemUploadKind): string {
  const lastPathPart = fileName.split(/[\\/]/).pop() || `${kind}-attachment`;
  const cleaned = lastPathPart.replace(/[^a-zA-Z0-9._-]/g, '-').replace(/-+/g, '-');
  return cleaned.slice(0, 120) || `${kind}-attachment`;
}

function encodeKey(key: string): string {
  return key.split('/').map(encodeURIComponent).join('/');
}

function publicFileUrl(bucket: string, region: string, key: string): string {
  const configuredBase = process.env.S3_PUBLIC_BASE_URL?.replace(/\/+$/, '');
  if (configuredBase) {
    return `${configuredBase}/${encodeKey(key)}`;
  }

  if (region === 'us-east-1') {
    return `https://${bucket}.s3.amazonaws.com/${encodeKey(key)}`;
  }

  return `https://${bucket}.s3.${region}.amazonaws.com/${encodeKey(key)}`;
}

export async function createItemAttachmentUpload(request: UploadRequest): Promise<UploadResponse> {
  const bucket = s3Bucket();
  const region = s3Region();
  const fileName = safeFileName(request.fileName, request.kind);
  const key = `homes/${request.homeId}/items/${request.kind}s/${randomUUID()}-${fileName}`;
  const headers = { 'Content-Type': request.contentType };

  const command = new PutObjectCommand({
    Bucket: bucket,
    Key: key,
    ContentType: request.contentType,
  });

  return {
    uploadUrl: await getSignedUrl(client(), command, { expiresIn: 5 * 60 }),
    fileUrl: publicFileUrl(bucket, region, key),
    key,
    headers,
  };
}
