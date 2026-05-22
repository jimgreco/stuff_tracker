import { randomUUID } from 'crypto';
import { GetObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { getIntegerEnv } from './env';

export type ItemUploadKind = 'photo' | 'document';

export class S3ConfigurationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'S3ConfigurationError';
  }
}

export class UploadLimitError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'UploadLimitError';
  }
}

export class UploadValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'UploadValidationError';
  }
}

interface UploadRequest {
  homeId: string;
  kind: ItemUploadKind;
  fileName: string;
  contentType: string;
  sizeBytes?: number;
}

interface UploadResponse {
  uploadUrl: string;
  fileUrl: string;
  key: string;
  headers: Record<string, string>;
}

interface StoredAttachmentValidationRequest {
  kind: ItemUploadKind;
  url: string;
  contentType?: string | null;
}

export interface StoredItemAttachments {
  photoUrls?: string[];
  documents?: Array<{
    url: string;
    content_type?: string | null;
  }>;
}

interface DetectedAttachmentType {
  family: 'image' | 'pdf' | 'archive' | 'compound' | 'text';
  mime: string;
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

export function maxUploadBytes(kind: ItemUploadKind): number {
  return kind === 'photo'
    ? getIntegerEnv('MAX_PHOTO_UPLOAD_BYTES', 10 * 1024 * 1024)
    : getIntegerEnv('MAX_DOCUMENT_UPLOAD_BYTES', 25 * 1024 * 1024);
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

function stableFileUrl(bucket: string, region: string, key: string): string {
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
  if (request.sizeBytes !== undefined && request.sizeBytes > maxUploadBytes(request.kind)) {
    throw new UploadLimitError(`${request.kind} upload exceeds the configured size limit`);
  }

  const bucket = s3Bucket();
  const region = s3Region();
  const fileName = safeFileName(request.fileName, request.kind);
  const key = `homes/${request.homeId}/items/${request.kind}s/${randomUUID()}-${fileName}`;
  const headers = { 'Content-Type': request.contentType };

  const command = new PutObjectCommand({
    Bucket: bucket,
    Key: key,
    ContentType: request.contentType,
    ContentLength: request.sizeBytes,
  });

  return {
    uploadUrl: await getSignedUrl(client(), command, { expiresIn: 5 * 60 }),
    fileUrl: await createItemAttachmentReadUrl(key),
    key,
    headers,
  };
}

export async function createItemAttachmentReadUrl(key: string): Promise<string> {
  const command = new GetObjectCommand({
    Bucket: s3Bucket(),
    Key: key,
  });

  return getSignedUrl(client(), command, {
    expiresIn: getIntegerEnv('S3_READ_URL_TTL_SECONDS', 60 * 60),
  });
}

export async function signStoredAttachmentUrl(url: string): Promise<string> {
  const key = attachmentKeyFromUrl(url);
  return key ? createItemAttachmentReadUrl(key) : url;
}

export async function validateStoredItemAttachments(attachments: StoredItemAttachments): Promise<void> {
  for (const photoUrl of attachments.photoUrls ?? []) {
    await validateStoredAttachmentBytes({ kind: 'photo', url: photoUrl, contentType: 'image/*' });
  }

  for (const document of attachments.documents ?? []) {
    await validateStoredAttachmentBytes({
      kind: 'document',
      url: document.url,
      contentType: document.content_type,
    });
  }
}

export async function validateStoredAttachmentBytes(request: StoredAttachmentValidationRequest): Promise<void> {
  const key = attachmentKeyFromUrl(request.url);
  if (!key) {
    return;
  }

  const bytes = await readObjectPrefix(key);
  assertAllowedAttachmentBytes(request.kind, request.contentType, bytes);
}

export function assertAllowedAttachmentBytes(
  kind: ItemUploadKind,
  contentType: string | null | undefined,
  bytes: Uint8Array
): void {
  const detected = detectAttachmentType(bytes);
  const normalizedContentType = normalizeContentType(contentType);

  if (kind === 'photo') {
    if (detected?.family !== 'image') {
      throw new UploadValidationError('Uploaded photo bytes do not match a supported image file');
    }
    return;
  }

  if (isImageContentType(normalizedContentType)) {
    if (detected?.family !== 'image') {
      throw new UploadValidationError('Uploaded document bytes do not match its image content type');
    }
    return;
  }

  if (normalizedContentType === 'application/pdf') {
    if (detected?.family !== 'pdf') {
      throw new UploadValidationError('Uploaded document bytes do not match its PDF content type');
    }
    return;
  }

  if (isArchiveContentType(normalizedContentType)) {
    if (detected?.family !== 'archive') {
      throw new UploadValidationError('Uploaded document bytes do not match its archive content type');
    }
    return;
  }

  if (isCompoundDocumentContentType(normalizedContentType)) {
    if (detected?.family !== 'compound') {
      throw new UploadValidationError('Uploaded document bytes do not match its Office document content type');
    }
    return;
  }

  if (isTextContentType(normalizedContentType)) {
    if (detected?.family !== 'text') {
      throw new UploadValidationError('Uploaded document bytes do not match its text content type');
    }
    return;
  }

  if (!detected) {
    throw new UploadValidationError('Uploaded document bytes do not match a supported file type');
  }
}

export function attachmentKeyFromUrl(value: string): string | undefined {
  if (value.startsWith('homes/')) {
    return value;
  }

  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch {
    return undefined;
  }

  const configuredBase = process.env.S3_PUBLIC_BASE_URL?.replace(/\/+$/, '');
  if (configuredBase && value.startsWith(`${configuredBase}/`)) {
    return decodeKeyPath(value.slice(configuredBase.length + 1).split('?')[0]);
  }

  const bucket = process.env.S3_BUCKET || process.env.AWS_S3_BUCKET;
  if (!bucket) {
    return undefined;
  }

  if (parsed.hostname === `${bucket}.s3.amazonaws.com` || parsed.hostname.startsWith(`${bucket}.s3.`)) {
    return decodeKeyPath(parsed.pathname.replace(/^\/+/, ''));
  }

  return undefined;
}

export function stableAttachmentUrlForKey(key: string): string {
  return stableFileUrl(s3Bucket(), s3Region(), key);
}

function decodeKeyPath(path: string): string {
  return path.split('/').map(decodeURIComponent).join('/');
}

async function readObjectPrefix(key: string): Promise<Uint8Array> {
  let response;
  try {
    response = await client().send(new GetObjectCommand({
      Bucket: s3Bucket(),
      Key: key,
      Range: 'bytes=0-511',
    }));
  } catch (err) {
    if (err instanceof S3ConfigurationError) {
      throw err;
    }
    throw new UploadValidationError('Uploaded attachment could not be read for validation');
  }

  return response.Body ? bodyToBytes(response.Body) : new Uint8Array();
}

async function bodyToBytes(body: unknown): Promise<Uint8Array> {
  if (body instanceof Uint8Array) {
    return body;
  }

  if (hasTransformToByteArray(body)) {
    return body.transformToByteArray();
  }

  if (isAsyncIterable(body)) {
    const chunks: Buffer[] = [];
    for await (const chunk of body) {
      chunks.push(Buffer.from(chunk));
    }
    return Buffer.concat(chunks);
  }

  throw new UploadValidationError('Uploaded attachment could not be read for validation');
}

function detectAttachmentType(bytes: Uint8Array): DetectedAttachmentType | undefined {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return { family: 'image', mime: 'image/jpeg' };
  }

  if (startsWith(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    return { family: 'image', mime: 'image/png' };
  }

  if (startsWithAscii(bytes, 'GIF87a') || startsWithAscii(bytes, 'GIF89a')) {
    return { family: 'image', mime: 'image/gif' };
  }

  if (bytes.length >= 12 && startsWithAscii(bytes, 'RIFF') && asciiAt(bytes, 8, 12) === 'WEBP') {
    return { family: 'image', mime: 'image/webp' };
  }

  if (isIsoImage(bytes)) {
    return { family: 'image', mime: 'image/heic' };
  }

  if (startsWith(bytes, [0x49, 0x49, 0x2a, 0x00]) || startsWith(bytes, [0x4d, 0x4d, 0x00, 0x2a])) {
    return { family: 'image', mime: 'image/tiff' };
  }

  if (startsWithAscii(bytes, '%PDF-')) {
    return { family: 'pdf', mime: 'application/pdf' };
  }

  if (startsWith(bytes, [0x50, 0x4b, 0x03, 0x04]) || startsWith(bytes, [0x50, 0x4b, 0x05, 0x06])) {
    return { family: 'archive', mime: 'application/zip' };
  }

  if (startsWith(bytes, [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1])) {
    return { family: 'compound', mime: 'application/vnd.ms-office' };
  }

  if (startsWithAscii(bytes, '{\\rtf') || looksLikeText(bytes)) {
    return { family: 'text', mime: 'text/plain' };
  }

  return undefined;
}

function normalizeContentType(contentType: string | null | undefined): string | undefined {
  return contentType?.split(';')[0]?.trim().toLowerCase() || undefined;
}

function isImageContentType(contentType: string | undefined): boolean {
  return contentType === 'image/*' || Boolean(contentType?.startsWith('image/'));
}

function isArchiveContentType(contentType: string | undefined): boolean {
  return contentType === 'application/zip'
    || contentType === 'application/x-zip-compressed'
    || contentType === 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    || contentType === 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    || contentType === 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
}

function isCompoundDocumentContentType(contentType: string | undefined): boolean {
  return contentType === 'application/msword'
    || contentType === 'application/vnd.ms-excel'
    || contentType === 'application/vnd.ms-powerpoint';
}

function isTextContentType(contentType: string | undefined): boolean {
  return Boolean(contentType?.startsWith('text/')) || contentType === 'application/json';
}

function isIsoImage(bytes: Uint8Array): boolean {
  if (bytes.length < 12 || asciiAt(bytes, 4, 8) !== 'ftyp') {
    return false;
  }

  const brand = asciiAt(bytes, 8, 12);
  return ['heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1', 'avif', 'avis'].includes(brand);
}

function looksLikeText(bytes: Uint8Array): boolean {
  if (bytes.length === 0) {
    return false;
  }

  for (const byte of bytes.slice(0, 512)) {
    if (byte === 0) {
      return false;
    }
    if (byte < 0x09 || (byte > 0x0d && byte < 0x20)) {
      return false;
    }
  }
  return true;
}

function startsWith(bytes: Uint8Array, prefix: number[]): boolean {
  return prefix.every((byte, index) => bytes[index] === byte);
}

function startsWithAscii(bytes: Uint8Array, prefix: string): boolean {
  return asciiAt(bytes, 0, prefix.length) === prefix;
}

function asciiAt(bytes: Uint8Array, start: number, end: number): string {
  return Buffer.from(bytes.slice(start, end)).toString('ascii');
}

function hasTransformToByteArray(body: unknown): body is { transformToByteArray(): Promise<Uint8Array> } {
  return typeof body === 'object'
    && body !== null
    && 'transformToByteArray' in body
    && typeof body.transformToByteArray === 'function';
}

function isAsyncIterable(body: unknown): body is AsyncIterable<Uint8Array> {
  return typeof body === 'object' && body !== null && Symbol.asyncIterator in body;
}
