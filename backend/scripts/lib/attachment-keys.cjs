// Used by serving and cleanup so all supported attachment URL forms retain the
// same object identity, including links with an expired read signature.
function attachmentKeyFromUrl(value) {
  if (typeof value !== 'string') return undefined;
  if (value.startsWith('homes/')) return value;
  let parsed;
  try { parsed = new URL(value); } catch { return undefined; }
  const base = process.env.S3_PUBLIC_BASE_URL?.replace(/\/+$/, '');
  if (base && value.startsWith(`${base}/`)) {
    return decodeKeyPath(value.slice(base.length + 1).split('?')[0]);
  }
  const bucket = process.env.S3_BUCKET || process.env.AWS_S3_BUCKET;
  if (bucket && (parsed.hostname === `${bucket}.s3.amazonaws.com` || parsed.hostname.startsWith(`${bucket}.s3.`))) {
    return decodeKeyPath(parsed.pathname.replace(/^\/+/, ''));
  }
  return undefined;
}

function decodeKeyPath(value) {
  return value.split('/').map(decodeURIComponent).join('/');
}

function referencedAttachmentKeys(rows) {
  const keys = new Set();
  for (const row of rows) {
    const values = [...(row.photo_urls || [])];
    for (const document of row.documents || []) values.push(document?.url, document?.id);
    for (const value of values) {
      const key = attachmentKeyFromUrl(value);
      if (key) keys.add(key);
    }
  }
  return keys;
}

module.exports = { attachmentKeyFromUrl, referencedAttachmentKeys };
