import test from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db/pool';
import {
  accountPlan,
  canCreateContainer,
  canCreateItem,
  canShareHome,
  canUpdateItemAttachments,
  canUploadAttachment,
  FREE_LIMITS,
} from '../src/lib/entitlements';

const originalQuery = pool.query.bind(pool);

test.afterEach(() => {
  (pool as any).query = originalQuery;
});

test('free account plan reports owned-home usage and remaining quota', async () => {
  mockEntitlementQueries({
    entitlementRows: [],
    usage: { containers: 25, items: 50, images: 2, documents: 1 },
  });

  const plan = await accountPlan('user-1');

  assert.equal(plan.tier, 'free');
  assert.equal(plan.isPaid, false);
  assert.equal(plan.usage.totalContainersAndItems, 75);
  assert.equal(plan.remaining.totalContainersAndItems, 25);
  assert.equal(plan.remaining.images, 3);
  assert.equal(plan.remaining.documents, 4);
});

test('active manual entitlement makes account paid regardless of usage', async () => {
  mockEntitlementQueries({
    entitlementRows: [{
      source: 'manual',
      product_id: null,
      expires_at: null,
      app_store_environment: null,
    }],
    usage: { containers: 120, items: 130, images: 30, documents: 40 },
  });

  const plan = await accountPlan('user-1');

  assert.equal(plan.tier, 'paid');
  assert.equal(plan.isPaid, true);
  assert.equal(plan.entitlement?.source, 'manual');
  assert.equal(plan.remaining.totalContainersAndItems, null);
});

test('free home owner is blocked at container, item, attachment, and sharing limits', async () => {
  mockEntitlementQueries({
    ownerId: 'owner-1',
    entitlementRows: [],
    usage: {
      containers: FREE_LIMITS.totalContainersAndItems,
      items: 0,
      images: FREE_LIMITS.images,
      documents: FREE_LIMITS.documents,
    },
  });

  assert.equal((await canCreateContainer('home-1'))?.code, 'free_container_item_limit');
  assert.equal((await canCreateItem('home-1', 0, 0))?.code, 'free_container_item_limit');
  assert.equal((await canUploadAttachment('home-1', 'photo'))?.code, 'free_image_limit');
  assert.equal((await canUploadAttachment('home-1', 'document'))?.code, 'free_document_limit');
  assert.equal((await canShareHome('home-1'))?.code, 'paid_required_for_sharing');
});

test('paid home owner can share and collaborators can add beyond free limits', async () => {
  mockEntitlementQueries({
    ownerId: 'owner-1',
    entitlementRows: [{
      source: 'app_store',
      product_id: 'com.jimgreco.stufftracker.pro.monthly',
      expires_at: new Date(Date.now() + 86_400_000),
      app_store_environment: 'Sandbox',
    }],
    usage: { containers: 200, items: 200, images: 200, documents: 200 },
  });

  assert.equal(await canCreateContainer('home-1'), null);
  assert.equal(await canCreateItem('home-1', 10, 10), null);
  assert.equal(await canUploadAttachment('home-1', 'photo'), null);
  assert.equal(await canShareHome('home-1'), null);
});

test('free account can reduce attachments even when already over limit', async () => {
  mockEntitlementQueries({
    ownerId: 'owner-1',
    entitlementRows: [],
    usage: { containers: 1, items: 1, images: 8, documents: 7 },
  });

  assert.equal(await canUpdateItemAttachments('home-1', 4, 1, 3, 1), null);
  assert.equal(
    (await canUpdateItemAttachments('home-1', 4, 5, 3, 3))?.code,
    'free_image_limit'
  );
});

function mockEntitlementQueries(options: {
  ownerId?: string;
  entitlementRows: any[];
  usage: { containers: number; items: number; images: number; documents: number };
}) {
  (pool as any).query = async (sql: string, _params?: unknown[]) => {
    const text = String(sql);
    if (text.includes('SELECT owner_id FROM homes')) {
      return { rows: options.ownerId ? [{ owner_id: options.ownerId }] : [] };
    }
    if (text.includes('FROM user_entitlements')) {
      return { rows: options.entitlementRows };
    }
    if (text.includes('FROM locations l') && text.includes('FROM items i')) {
      return { rows: [options.usage] };
    }
    throw new Error(`Unexpected query: ${text}`);
  };
}
