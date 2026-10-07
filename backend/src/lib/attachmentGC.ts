import type { PoolClient } from 'pg';

export const { lockAttachmentReferences, assertAttachmentsAvailable, AttachmentRetiredError } =
  require('../../scripts/lib/attachment-gc.cjs') as {
    lockAttachmentReferences(client: PoolClient): Promise<void>;
    assertAttachmentsAvailable(client: PoolClient, attachments: { photo_urls?: string[]; documents?: unknown[] }): Promise<void>;
    AttachmentRetiredError: new () => Error;
  };
