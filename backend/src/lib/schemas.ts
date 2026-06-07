import { z } from 'zod';

export const LocationTypeSchema = z.enum(['floor', 'room', 'container']);
const IconSchema = z.string().trim().min(1).max(100).nullable().optional();
const DateStringSchema = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional();
const OptionalTrimmedTextSchema = (max: number) => z.string().trim().max(max).nullable().optional();

export const LocationSchema = z.object({
  home_id: z.string().uuid().optional(),
  name: z.string().min(1).max(200),
  parent_id: z.string().uuid().nullable().optional(),
  type: LocationTypeSchema,
  sort_order: z.number().int().optional(),
  icon: IconSchema,
  is_flagged: z.boolean().optional(),
});

export const ItemDocumentSchema = z.object({
  id: z.string().min(1).max(1024),
  url: z.string().url(),
  name: z.string().min(1).max(255),
  content_type: z.string().max(255).nullable().optional(),
});

export const ItemPropertySchema = z.object({
  id: z.string().min(1).max(100),
  key: z.string().trim().min(1).max(100),
  value: z.string().trim().max(1000),
});

export const ItemSchema = z.object({
  home_id: z.string().uuid().optional(),
  name: z.string().min(1).max(200),
  location_id: z.string().uuid().nullable().optional(),
  icon: IconSchema,
  notes: z.string().max(2000).nullable().optional(),
  quantity: z.number().int().min(1).optional(),
  properties: z.array(ItemPropertySchema).max(100).optional(),
  photo_urls: z.array(z.string().url()).max(50).optional(),
  documents: z.array(ItemDocumentSchema).max(50).optional(),
  purchase_date: DateStringSchema,
  serial_number: OptionalTrimmedTextSchema(200),
  model_number: OptionalTrimmedTextSchema(200),
  warranty_expires_date: DateStringSchema,
  estimated_value_cents: z.number().int().min(0).nullable().optional(),
  is_flagged: z.boolean().optional(),
  sort_order: z.number().int().optional(),
});

export const ItemUploadSchema = z.preprocess((value) => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return value;
  }

  const body = value as Record<string, unknown>;
  return {
    ...body,
    file_name: body.file_name ?? body.fileName,
    content_type: body.content_type ?? body.contentType,
    size_bytes: body.size_bytes ?? body.sizeBytes,
  };
}, z.object({
  kind: z.enum(['photo', 'document']),
  file_name: z.string().min(1).max(255),
  content_type: z.string().min(1).max(255),
  size_bytes: z.number().int().min(1).max(50 * 1024 * 1024).optional(),
}));

export const HomeNameSchema = z.object({
  name: z.string().min(1).max(100),
});

export const HomeSchema = z.object({
  name: z.string().min(1).max(100),
  icon: IconSchema,
  is_flagged: z.boolean().optional(),
});

export const MemberRoleSchema = z.enum(['admin', 'editor', 'viewer']);

export const InviteSchema = z.object({
  email: z.string().trim().toLowerCase().email(),
  role: MemberRoleSchema,
});

export const UpdateMemberRoleSchema = z.object({
  role: MemberRoleSchema,
});

export const AppStoreTransactionSyncSchema = z.preprocess((value) => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return value;
  }

  const body = value as Record<string, unknown>;
  return {
    ...body,
    signed_transaction_info: body.signed_transaction_info ?? body.signedTransactionInfo,
  };
}, z.object({
  signed_transaction_info: z.string().min(1).max(50_000),
}));

export const ManualEntitlementGrantSchema = z.object({
  email: z.string().trim().toLowerCase().email(),
  source: z.enum(['manual', 'promo', 'admin']).default('manual'),
  expires_at: z.string().datetime().nullable().optional(),
});
