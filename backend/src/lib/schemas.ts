import { z } from 'zod';

export const LocationTypeSchema = z.enum(['floor', 'room', 'container']);

export const LocationSchema = z.object({
  name: z.string().min(1).max(200),
  parent_id: z.string().uuid().nullable().optional(),
  type: LocationTypeSchema,
  sort_order: z.number().int().optional(),
});

export const ItemSchema = z.object({
  name: z.string().min(1).max(200),
  location_id: z.string().uuid().nullable().optional(),
  notes: z.string().max(2000).nullable().optional(),
  quantity: z.number().int().min(1).optional(),
  tags: z.array(z.string()).optional(),
  photo_url: z.string().url().nullable().optional(),
  purchase_date: z.string().nullable().optional(),
});

export const HomeNameSchema = z.object({
  name: z.string().min(1).max(100),
});

export const MemberRoleSchema = z.enum(['admin', 'editor', 'viewer']);

export const InviteSchema = z.object({
  email: z.string().email(),
  role: MemberRoleSchema,
});

export const UpdateMemberRoleSchema = z.object({
  role: MemberRoleSchema,
});
