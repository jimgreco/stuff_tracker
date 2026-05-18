import { signStoredAttachmentUrl } from './s3';

interface ItemDocumentRow {
  url?: unknown;
  [key: string]: unknown;
}

interface ItemRow {
  photo_urls?: unknown;
  documents?: unknown;
  [key: string]: unknown;
}

export async function signItemAttachmentUrls<T extends ItemRow>(item: T): Promise<T> {
  const next = { ...item };

  if (Array.isArray(item.photo_urls)) {
    next.photo_urls = await Promise.all(
      item.photo_urls.map((url) => typeof url === 'string' ? signStoredAttachmentUrl(url) : url)
    );
  }

  if (Array.isArray(item.documents)) {
    next.documents = await Promise.all(
      item.documents.map(async (document): Promise<ItemDocumentRow> => {
        if (!isDocumentRow(document) || typeof document.url !== 'string') {
          return document as ItemDocumentRow;
        }

        return {
          ...document,
          url: await signStoredAttachmentUrl(document.url),
        };
      })
    );
  }

  return next;
}

export async function signItemsAttachmentUrls<T extends ItemRow>(items: T[]): Promise<T[]> {
  return Promise.all(items.map(signItemAttachmentUrls));
}

function isDocumentRow(value: unknown): value is ItemDocumentRow {
  return Boolean(value) && typeof value === 'object';
}
