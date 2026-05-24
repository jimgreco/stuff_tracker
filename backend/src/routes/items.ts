import { Router, Response } from 'express';
import { pool } from '../db/pool';
import { requireAuth, AuthRequest } from '../middleware/auth';
import { getHomeRole, canEdit } from '../lib/access';
import { ItemSchema, ItemUploadSchema } from '../lib/schemas';
import {
  createItemAttachmentUpload,
  maxUploadBytes,
  S3ConfigurationError,
  UploadLimitError,
  UploadValidationError,
  validateStoredItemAttachments,
} from '../lib/s3';
import { signItemAttachmentUrls, signItemsAttachmentUrls } from '../lib/attachmentResponses';
import { uploadRateLimit } from '../lib/rateLimits';

const router = Router({ mergeParams: true });
router.use(requireAuth);

// ── Create a direct-to-S3 upload URL for item attachments ─────────────────────
router.post('/uploads', uploadRateLimit, async (req: AuthRequest, res: Response) => {
  const { homeId } = req.params;
  const role = await getHomeRole(homeId, req.user!.userId);
  if (!canEdit(role)) { res.status(403).json({ error: 'Edit access required' }); return; }

  const { kind, file_name, content_type, size_bytes } = ItemUploadSchema.parse(req.body);
  if (kind === 'photo' && !content_type.startsWith('image/')) {
    res.status(400).json({ error: 'Photo uploads must use an image content type' });
    return;
  }
  if (size_bytes !== undefined && size_bytes > maxUploadBytes(kind)) {
    res.status(413).json({ error: `${kind} upload exceeds the configured size limit` });
    return;
  }

  try {
    const upload = await createItemAttachmentUpload({
      homeId,
      kind,
      fileName: file_name,
      contentType: content_type,
      sizeBytes: size_bytes,
    });
    res.status(201).json(upload);
  } catch (err) {
    if (err instanceof UploadLimitError) {
      res.status(413).json({ error: err.message });
      return;
    }
    if (err instanceof S3ConfigurationError) {
      res.status(503).json({ error: err.message });
      return;
    }
    throw err;
  }
});

// ── Create item ────────────────────────────────────────────────────────────────
router.post('/', async (req: AuthRequest, res: Response) => {
  const { homeId } = req.params;
  const role = await getHomeRole(homeId, req.user!.userId);
  if (!canEdit(role)) { res.status(403).json({ error: 'Edit access required' }); return; }

  const {
    name,
    location_id,
    icon,
    notes,
    quantity,
    properties,
    photo_urls,
    documents,
    purchase_date,
    serial_number,
    model_number,
    warranty_expires_date,
    estimated_value_cents,
  } = ItemSchema.parse(req.body);
  if (location_id) {
    const location = await pool.query(
      'SELECT id FROM locations WHERE id = $1 AND home_id = $2',
      [location_id, homeId]
    );
    if (!location.rows[0]) {
      res.status(400).json({ error: 'Location not found' });
      return;
    }
  }
  if (!await validateAttachmentsOrRespond(res, { photoUrls: photo_urls, documents })) {
    return;
  }

  const { rows } = await pool.query(
    `INSERT INTO items (
       home_id, location_id, name, icon, notes, quantity, properties, photo_urls,
       documents, purchase_date, serial_number, model_number, warranty_expires_date,
       estimated_value_cents, created_by
     )
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
     RETURNING *`,
    [
      homeId,
      location_id ?? null,
      name,
      icon ?? null,
      notes ?? null,
      quantity ?? 1,
      JSON.stringify(properties ?? []),
      photo_urls ?? [],
      JSON.stringify(documents ?? []),
      purchase_date ?? null,
      serial_number ?? null,
      model_number ?? null,
      warranty_expires_date ?? null,
      estimated_value_cents ?? null,
      req.user!.userId,
    ]
  );
  res.status(201).json(await signItemAttachmentUrls(rows[0]));
});

// ── Update item ────────────────────────────────────────────────────────────────
router.patch('/:itemId', async (req: AuthRequest, res: Response) => {
  const { homeId, itemId } = req.params;
  const role = await getHomeRole(homeId, req.user!.userId);
  if (!canEdit(role)) { res.status(403).json({ error: 'Edit access required' }); return; }

  const updates = ItemSchema.partial().parse(req.body);
  if (updates.location_id) {
    const location = await pool.query(
      'SELECT id FROM locations WHERE id = $1 AND home_id = $2',
      [updates.location_id, homeId]
    );
    if (!location.rows[0]) {
      res.status(400).json({ error: 'Location not found' });
      return;
    }
  }

  const fields: string[] = [];
  const values: unknown[] = [];
  let i = 1;

  const allowed = [
    'name',
    'location_id',
    'icon',
    'notes',
    'quantity',
    'properties',
    'photo_urls',
    'documents',
    'purchase_date',
    'serial_number',
    'model_number',
    'warranty_expires_date',
    'estimated_value_cents',
  ] as const;
  for (const key of allowed) {
    if (key in updates) {
      fields.push(`${key} = $${i++}`);
      const value = (updates as Record<string, unknown>)[key];
      values.push(key === 'documents' || key === 'properties' ? JSON.stringify(value ?? []) : value ?? null);
    }
  }
  if (!fields.length) { res.status(400).json({ error: 'Nothing to update' }); return; }
  if (!await validateAttachmentsOrRespond(res, {
    photoUrls: updates.photo_urls,
    documents: updates.documents,
  })) {
    return;
  }

  fields.push(`updated_at = NOW()`);
  values.push(itemId, homeId);

  const { rows } = await pool.query(
    `UPDATE items SET ${fields.join(', ')}
     WHERE id = $${i++} AND home_id = $${i} RETURNING *`,
    values
  );
  if (!rows[0]) { res.status(404).json({ error: 'Item not found' }); return; }
  res.json(await signItemAttachmentUrls(rows[0]));
});

// ── Delete item ────────────────────────────────────────────────────────────────
router.delete('/:itemId', async (req: AuthRequest, res: Response) => {
  const { homeId, itemId } = req.params;
  const role = await getHomeRole(homeId, req.user!.userId);
  if (!canEdit(role)) { res.status(403).json({ error: 'Edit access required' }); return; }

  await pool.query('DELETE FROM items WHERE id = $1 AND home_id = $2', [itemId, homeId]);
  res.status(204).send();
});

// ── Search items within a home ─────────────────────────────────────────────────
router.get('/search', async (req: AuthRequest, res: Response) => {
  const { homeId } = req.params;
  const role = await getHomeRole(homeId, req.user!.userId);
  if (!role) { res.status(403).json({ error: 'Access denied' }); return; }

  const q = String(req.query.q ?? '').trim();
  if (!q) { res.json([]); return; }

  const searchVector = `to_tsvector('english', i.name || ' ' || COALESCE(i.notes, '') || ' ' || COALESCE(i.properties::text, '') || ' ' || COALESCE(i.serial_number, '') || ' ' || COALESCE(i.model_number, ''))`;
  const { rows } = await pool.query(
    `SELECT i.*, l.name AS location_name, l.parent_id AS location_parent_id
     FROM items i
     LEFT JOIN locations l ON l.id = i.location_id
     WHERE i.home_id = $1
       AND ${searchVector} @@ plainto_tsquery('english', $2)
     ORDER BY ts_rank(${searchVector}, plainto_tsquery('english', $2)) DESC
     LIMIT 50`,
    [homeId, q]
  );
  res.json(await signItemsAttachmentUrls(rows));
});

export default router;

async function validateAttachmentsOrRespond(
  res: Response,
  attachments: Parameters<typeof validateStoredItemAttachments>[0]
): Promise<boolean> {
  try {
    await validateStoredItemAttachments(attachments);
    return true;
  } catch (err) {
    if (err instanceof UploadValidationError) {
      res.status(400).json({ error: err.message });
      return false;
    }
    if (err instanceof S3ConfigurationError) {
      res.status(503).json({ error: err.message });
      return false;
    }
    throw err;
  }
}
