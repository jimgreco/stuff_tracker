import { pool } from '../db/pool';

export const FREE_LIMITS = {
  totalContainersAndItems: 100,
  images: 5,
  documents: 5,
} as const;

export type EntitlementSource = 'app_store' | 'manual' | 'promo' | 'admin';
export type EntitlementStatus = 'active' | 'expired' | 'revoked';
export type AttachmentKind = 'photo' | 'document';

export type AccountPlan = {
  tier: 'free' | 'paid';
  isPaid: boolean;
  entitlement: ActiveEntitlement | null;
  limits: typeof FREE_LIMITS;
  usage: QuotaUsage;
  remaining: QuotaRemaining;
};

export type ActiveEntitlement = {
  source: EntitlementSource;
  productId: string | null;
  expiresAt: string | null;
  appStoreEnvironment: string | null;
};

export type QuotaUsage = {
  containers: number;
  items: number;
  totalContainersAndItems: number;
  images: number;
  documents: number;
};

export type QuotaRemaining = {
  totalContainersAndItems: number | null;
  images: number | null;
  documents: number | null;
};

export type QuotaDecision = {
  allowed: boolean;
  status: number;
  error: string;
  code: string;
  plan: AccountPlan;
};

type OwnerRow = {
  owner_id: string;
};

type EntitlementRow = {
  source: EntitlementSource;
  product_id: string | null;
  expires_at: Date | null;
  app_store_environment: string | null;
};

type UsageRow = {
  containers: string | number | null;
  items: string | number | null;
  images: string | number | null;
  documents: string | number | null;
};

export async function accountPlan(userId: string): Promise<AccountPlan> {
  const [entitlement, usage] = await Promise.all([
    activeEntitlement(userId),
    quotaUsage(userId),
  ]);

  const isPaid = Boolean(entitlement);
  return {
    tier: isPaid ? 'paid' : 'free',
    isPaid,
    entitlement,
    limits: FREE_LIMITS,
    usage,
    remaining: {
      totalContainersAndItems: isPaid ? null : Math.max(0, FREE_LIMITS.totalContainersAndItems - usage.totalContainersAndItems),
      images: isPaid ? null : Math.max(0, FREE_LIMITS.images - usage.images),
      documents: isPaid ? null : Math.max(0, FREE_LIMITS.documents - usage.documents),
    },
  };
}

export async function activeEntitlement(userId: string): Promise<ActiveEntitlement | null> {
  const { rows } = await pool.query<EntitlementRow>(
    `SELECT source, product_id, expires_at, app_store_environment
     FROM user_entitlements
     WHERE user_id = $1
       AND status = 'active'
       AND revoked_at IS NULL
       AND (expires_at IS NULL OR expires_at > NOW())
     ORDER BY
       CASE WHEN expires_at IS NULL THEN 0 ELSE 1 END,
       expires_at DESC NULLS FIRST,
       updated_at DESC
     LIMIT 1`,
    [userId]
  );

  const row = rows[0];
  if (!row) {
    return null;
  }

  return {
    source: row.source,
    productId: row.product_id,
    expiresAt: row.expires_at?.toISOString() ?? null,
    appStoreEnvironment: row.app_store_environment,
  };
}

export async function quotaUsage(userId: string): Promise<QuotaUsage> {
  const { rows } = await pool.query<UsageRow>(
    `SELECT
       COALESCE((
         SELECT COUNT(*)
         FROM locations l
         JOIN homes h ON h.id = l.home_id
         WHERE h.owner_id = $1 AND l.type = 'container'
       ), 0) AS containers,
       COALESCE((
         SELECT COUNT(*)
         FROM items i
         JOIN homes h ON h.id = i.home_id
         WHERE h.owner_id = $1
       ), 0) AS items,
       COALESCE((
         SELECT SUM(cardinality(i.photo_urls))
         FROM items i
         JOIN homes h ON h.id = i.home_id
         WHERE h.owner_id = $1
       ), 0) AS images,
       COALESCE((
         SELECT SUM(jsonb_array_length(i.documents))
         FROM items i
         JOIN homes h ON h.id = i.home_id
         WHERE h.owner_id = $1
       ), 0) AS documents`,
    [userId]
  );

  const row = rows[0] ?? { containers: 0, items: 0, images: 0, documents: 0 };
  const containers = countValue(row.containers);
  const items = countValue(row.items);
  return {
    containers,
    items,
    totalContainersAndItems: containers + items,
    images: countValue(row.images),
    documents: countValue(row.documents),
  };
}

export async function homeOwnerId(homeId: string): Promise<string | null> {
  const { rows } = await pool.query<OwnerRow>('SELECT owner_id FROM homes WHERE id = $1', [homeId]);
  return rows[0]?.owner_id ?? null;
}

export async function canCreateContainer(homeId: string): Promise<QuotaDecision | null> {
  const ownerId = await homeOwnerId(homeId);
  if (!ownerId) {
    return null;
  }

  const plan = await accountPlan(ownerId);
  if (plan.isPaid || plan.usage.totalContainersAndItems < FREE_LIMITS.totalContainersAndItems) {
    return null;
  }

  return quotaBlocked(
    plan,
    'free_container_item_limit',
    `Free accounts can store up to ${FREE_LIMITS.totalContainersAndItems} containers and items. Upgrade to add more.`
  );
}

export async function canCreateItem(
  homeId: string,
  photoCount: number,
  documentCount: number
): Promise<QuotaDecision | null> {
  const ownerId = await homeOwnerId(homeId);
  if (!ownerId) {
    return null;
  }

  const plan = await accountPlan(ownerId);
  if (plan.isPaid) {
    return null;
  }

  if (plan.usage.totalContainersAndItems >= FREE_LIMITS.totalContainersAndItems) {
    return quotaBlocked(
      plan,
      'free_container_item_limit',
      `Free accounts can store up to ${FREE_LIMITS.totalContainersAndItems} containers and items. Upgrade to add more.`
    );
  }

  if (plan.usage.images + photoCount > FREE_LIMITS.images) {
    return quotaBlocked(
      plan,
      'free_image_limit',
      `Free accounts can store up to ${FREE_LIMITS.images} images. Upgrade to add more.`
    );
  }

  if (plan.usage.documents + documentCount > FREE_LIMITS.documents) {
    return quotaBlocked(
      plan,
      'free_document_limit',
      `Free accounts can store up to ${FREE_LIMITS.documents} documents. Upgrade to add more.`
    );
  }

  return null;
}

export async function canUploadAttachment(homeId: string, kind: AttachmentKind): Promise<QuotaDecision | null> {
  const ownerId = await homeOwnerId(homeId);
  if (!ownerId) {
    return null;
  }

  const plan = await accountPlan(ownerId);
  if (plan.isPaid) {
    return null;
  }

  if (kind === 'photo' && plan.usage.images >= FREE_LIMITS.images) {
    return quotaBlocked(
      plan,
      'free_image_limit',
      `Free accounts can store up to ${FREE_LIMITS.images} images. Upgrade to add more.`
    );
  }

  if (kind === 'document' && plan.usage.documents >= FREE_LIMITS.documents) {
    return quotaBlocked(
      plan,
      'free_document_limit',
      `Free accounts can store up to ${FREE_LIMITS.documents} documents. Upgrade to add more.`
    );
  }

  return null;
}

export async function canUpdateItemAttachments(
  homeId: string,
  currentPhotoCount: number,
  nextPhotoCount: number | undefined,
  currentDocumentCount: number,
  nextDocumentCount: number | undefined
): Promise<QuotaDecision | null> {
  const ownerId = await homeOwnerId(homeId);
  if (!ownerId) {
    return null;
  }

  const plan = await accountPlan(ownerId);
  if (plan.isPaid) {
    return null;
  }

  if (nextPhotoCount !== undefined) {
    const projectedImages = plan.usage.images - currentPhotoCount + nextPhotoCount;
    if (projectedImages > FREE_LIMITS.images) {
      return quotaBlocked(
        plan,
        'free_image_limit',
        `Free accounts can store up to ${FREE_LIMITS.images} images. Upgrade to add more.`
      );
    }
  }

  if (nextDocumentCount !== undefined) {
    const projectedDocuments = plan.usage.documents - currentDocumentCount + nextDocumentCount;
    if (projectedDocuments > FREE_LIMITS.documents) {
      return quotaBlocked(
        plan,
        'free_document_limit',
        `Free accounts can store up to ${FREE_LIMITS.documents} documents. Upgrade to add more.`
      );
    }
  }

  return null;
}

export async function canShareHome(homeId: string): Promise<QuotaDecision | null> {
  const ownerId = await homeOwnerId(homeId);
  if (!ownerId) {
    return null;
  }

  const plan = await accountPlan(ownerId);
  if (plan.isPaid) {
    return null;
  }

  return quotaBlocked(
    plan,
    'paid_required_for_sharing',
    'Sharing requires a paid account for the home owner.'
  );
}

function quotaBlocked(plan: AccountPlan, code: string, error: string): QuotaDecision {
  return {
    allowed: false,
    status: 402,
    error,
    code,
    plan,
  };
}

function countValue(value: string | number | null | undefined): number {
  if (typeof value === 'number') {
    return value;
  }
  if (typeof value === 'string') {
    return Number(value);
  }
  return 0;
}
