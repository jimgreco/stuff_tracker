import { pool } from '../db/pool';

export const FREE_LIMITS = {
  homes: 1,
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
  homes: number;
  containers: number;
  items: number;
  totalContainersAndItems: number;
  images: number;
  documents: number;
};

export type QuotaRemaining = {
  homes: number | null;
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
  homes: string | number | null;
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
      homes: isPaid ? null : Math.max(0, FREE_LIMITS.homes - usage.homes),
      totalContainersAndItems: null,
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
         FROM homes h
         WHERE h.owner_id = $1
       ), 0) AS homes,
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

  const row = rows[0] ?? { homes: 0, containers: 0, items: 0, images: 0, documents: 0 };
  const containers = countValue(row.containers);
  const items = countValue(row.items);
  return {
    homes: countValue(row.homes),
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

export async function canCreateHome(userId: string): Promise<QuotaDecision | null> {
  const plan = await accountPlan(userId);
  if (plan.isPaid) {
    return null;
  }

  if (plan.usage.homes >= FREE_LIMITS.homes) {
    return quotaBlocked(
      plan,
      'free_home_limit',
      homeLimitMessage()
    );
  }

  return null;
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

  if (photoCount > 0) {
    return quotaBlocked(
      plan,
      'paid_required_for_photos',
      photoRequiredMessage()
    );
  }

  if (documentCount > 0) {
    return quotaBlocked(
      plan,
      'paid_required_for_documents',
      documentRequiredMessage()
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

  if (kind === 'photo') {
    return quotaBlocked(
      plan,
      'paid_required_for_photos',
      photoRequiredMessage()
    );
  }

  if (kind === 'document') {
    return quotaBlocked(
      plan,
      'paid_required_for_documents',
      documentRequiredMessage()
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
    if (nextPhotoCount > currentPhotoCount) {
      return quotaBlocked(
        plan,
        'paid_required_for_photos',
        photoRequiredMessage()
      );
    }
  }

  if (nextDocumentCount !== undefined) {
    if (nextDocumentCount > currentDocumentCount) {
      return quotaBlocked(
        plan,
        'paid_required_for_documents',
        documentRequiredMessage()
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
    'Sharing requires Pro for the home owner. Subscribe to Pro to share homes with collaborators and store more photos and documents.'
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

function homeLimitMessage(): string {
  return `Free accounts can create one home. Subscribe to Pro to add more homes, photos, documents, and collaborators.`;
}

function photoRequiredMessage(): string {
  return 'Adding photos requires Pro. Subscribe to Pro to store photos and documents and share homes with collaborators.';
}

function documentRequiredMessage(): string {
  return 'Adding documents requires Pro. Subscribe to Pro to store photos and documents and share homes with collaborators.';
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
