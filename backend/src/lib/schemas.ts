import { z } from 'zod';

export const LocationTypeSchema = z.enum(['floor', 'room', 'container']);

export const LocationSchema = z.object({
  name: z.string().min(1).max(200),
  parent_id: z.string().uuid().nullable().optional(),
  type: LocationTypeSchema,
  sort_order: z.number().int().optional(),
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
  name: z.string().min(1).max(200),
  location_id: z.string().uuid().nullable().optional(),
  notes: z.string().max(2000).nullable().optional(),
  quantity: z.number().int().min(1).optional(),
  properties: z.array(ItemPropertySchema).max(100).optional(),
  photo_urls: z.array(z.string().url()).max(50).optional(),
  documents: z.array(ItemDocumentSchema).max(50).optional(),
  purchase_date: z.string().nullable().optional(),
});

export const ItemUploadSchema = z.object({
  kind: z.enum(['photo', 'document']),
  file_name: z.string().min(1).max(255),
  content_type: z.string().min(1).max(255),
});

export const HomeNameSchema = z.object({
  name: z.string().min(1).max(100),
});

export const MemberRoleSchema = z.enum(['admin', 'editor', 'viewer']);

export const InviteSchema = z.object({
  email: z.string().trim().toLowerCase().email(),
  role: MemberRoleSchema,
});

export const UpdateMemberRoleSchema = z.object({
  role: MemberRoleSchema,
});
