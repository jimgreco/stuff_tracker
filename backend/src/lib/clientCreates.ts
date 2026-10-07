import { createHash } from 'node:crypto';
import type { PoolClient } from 'pg';
import { z } from 'zod';
import { pool } from '../db/pool';
import type { AuthRequest } from '../middleware/auth';
import { withActivityTransaction } from './activity';

export const ClientIDSchema = z.string().uuid().transform((id) => id.toLowerCase()).optional();
type EntityType = 'home' | 'location' | 'item';
const tables = { home: 'homes', location: 'locations', item: 'items' } as const;
export class ClientCreateError extends Error {
  constructor(readonly status: number, readonly code: string, message: string) { super(message); }
}

type CreateIdentity = {
  userID: string; kind: EntityType; clientID?: string; homeID: string | null; hash: string;
};

// Normalize object key order recursively. Array order and field values are part
// of the request; reusing an original ID with a changed POST is a conflict.
export function createIdentity(userID: string, kind: EntityType, clientID: string | undefined,
  homeID: string | null, body: unknown): CreateIdentity {
  const canonical = (value: any): any => Array.isArray(value) ? value.map(canonical)
    : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort()
      .filter((key) => value[key] !== undefined).map((key) => [key, canonical(value[key])])) : value;
  return { userID, kind, clientID, homeID: homeID?.toLowerCase() ?? null,
    hash: createHash('sha256').update(JSON.stringify(canonical({ homeID: homeID?.toLowerCase() ?? null, body }))).digest('hex') };
}

// Read-only early replay avoids charging quota/revalidating expired media for an
// effect already committed. The transaction repeats this lookup before any INSERT.
export async function replayClientCreate(identity: CreateIdentity, db: Pick<PoolClient, 'query'> = pool): Promise<any | undefined> {
  if (!identity.clientID) return undefined;
  const receipt = (await db.query(`SELECT home_id, request_hash, resource_id, deleted_at FROM client_create_receipts
    WHERE user_id = $1 AND entity_type = $2 AND client_id = $3`,
  [identity.userID, identity.kind, identity.clientID])).rows[0];
  if (!receipt) return undefined;
  if (receipt.deleted_at) throw new ClientCreateError(410, 'client_create_deleted', 'This original create was deleted or cancelled. Review the retained local record.');
  if (receipt.home_id !== identity.homeID || receipt.request_hash !== identity.hash) {
    throw new ClientCreateError(409, 'client_create_conflict', 'This original create ID was already used for different data. Review before retrying.');
  }
  const record = (await db.query(`SELECT * FROM ${tables[identity.kind]} WHERE id = $1`, [receipt.resource_id])).rows[0];
  if (!record) throw new ClientCreateError(410, 'client_create_deleted', 'The original create no longer exists. Review the retained local record.');
  if (identity.kind === 'home' && record.owner_id !== identity.userID) {
    throw new ClientCreateError(403, 'client_create_access', 'Access to the original create is no longer available.');
  }
  if (identity.kind !== 'home' && record.home_id !== identity.homeID) {
    throw new ClientCreateError(409, 'client_create_moved', 'The original create moved to another home. Refresh before retrying.');
  }
  return record;
}

export async function withClientCreate(req: AuthRequest, identity: CreateIdentity,
  create: (client: PoolClient, clientID?: string) => Promise<any>): Promise<any> {
  try {
    return await withActivityTransaction(req, async (client) => {
      const previous = await replayClientCreate(identity, client);
      if (previous) return previous;
      const result = await create(client, identity.clientID);
      if (identity.clientID) {
        await client.query(`INSERT INTO client_create_receipts
          (user_id, entity_type, client_id, home_id, request_hash, resource_id) VALUES ($1, $2, $3, $4, $5, $3)`,
        [identity.userID, identity.kind, identity.clientID, identity.homeID, identity.hash]);
      }
      return result;
    });
  } catch (error) {
    if ((error as { code?: string; constraint?: string }).code === '23505'
      && (error as { constraint?: string }).constraint === `${tables[identity.kind]}_pkey`) {
      throw new ClientCreateError(409, 'client_id_collision', 'This original ID is already in use. Review the retained record.');
    }
    throw error;
  }
}

export function deleteClientID(req: AuthRequest, resourceID: string): string | undefined {
  const id = ClientIDSchema.parse(req.query.client_id);
  if (id && id !== resourceID.toLowerCase()) {
    throw new ClientCreateError(400, 'invalid_client_id', 'Original ID must match the resource being deleted.');
  }
  return id;
}

// Must execute in the same inventory transaction as DELETE, including when the
// resource does not yet exist. It serializes a delete that overtakes a delayed POST.
export async function cancelClientCreate(client: PoolClient, userID: string, kind: EntityType,
  clientID: string | undefined, homeID: string | null): Promise<void> {
  if (!clientID) return;
  const receipt = (await client.query(`SELECT home_id FROM client_create_receipts
    WHERE user_id = $1 AND entity_type = $2 AND client_id = $3`, [userID, kind, clientID])).rows[0];
  const record = (await client.query(`SELECT * FROM ${tables[kind]} WHERE id = $1`, [clientID])).rows[0];
  if (kind !== 'home' && ((record && record.home_id !== homeID) || (!record && receipt && receipt.home_id !== homeID))) {
    throw new ClientCreateError(409, 'client_create_moved', 'Original create belongs to another home. Refresh before deleting.');
  }
  await client.query(`INSERT INTO client_create_receipts
    (user_id, entity_type, client_id, home_id, resource_id, deleted_at) VALUES ($1, $2, $3, $4, $3, NOW())
    ON CONFLICT (user_id, entity_type, client_id) DO UPDATE SET deleted_at = COALESCE(client_create_receipts.deleted_at, NOW())`,
  [userID, kind, clientID, homeID]);
}
