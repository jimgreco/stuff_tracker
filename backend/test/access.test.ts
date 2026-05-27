import test from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db/pool';
import { canAdmin, canEdit, getHomeRole } from '../src/lib/access';
import type { Role } from '../src/lib/access';

const originalQuery = pool.query.bind(pool);

test.afterEach(() => {
  (pool as any).query = originalQuery;
});

test('canEdit allows owner, admin, and editor roles only', () => {
  const editableRoles: Array<Role | null> = ['owner', 'admin', 'editor'];
  const readonlyRoles: Array<Role | null> = ['viewer', null];

  for (const role of editableRoles) {
    assert.equal(canEdit(role), true, `${role} should edit`);
  }

  for (const role of readonlyRoles) {
    assert.equal(canEdit(role), false, `${role} should not edit`);
  }
});

test('canAdmin allows owner and admin roles only', () => {
  const adminRoles: Array<Role | null> = ['owner', 'admin'];
  const nonAdminRoles: Array<Role | null> = ['editor', 'viewer', null];

  for (const role of adminRoles) {
    assert.equal(canAdmin(role), true, `${role} should admin`);
  }

  for (const role of nonAdminRoles) {
    assert.equal(canAdmin(role), false, `${role} should not admin`);
  }
});

test('getHomeRole returns owner access regardless of entitlement', async () => {
  (pool as any).query = async (sql: string) => {
    if (String(sql).includes('SELECT id FROM homes')) {
      return { rows: [{ id: 'home-1' }] };
    }
    throw new Error(`Unexpected query: ${sql}`);
  };

  assert.equal(await getHomeRole('home-1', 'owner-1'), 'owner');
});

test('getHomeRole requires a paid owner for shared member access', async () => {
  let ownerIsPaid = false;
  (pool as any).query = async (sql: string) => {
    const text = String(sql);
    if (text.includes('SELECT id FROM homes')) {
      return { rows: [] };
    }
    if (text.includes('FROM home_members hm')) {
      return { rows: [{ role: 'editor', owner_is_paid: ownerIsPaid }] };
    }
    throw new Error(`Unexpected query: ${text}`);
  };

  assert.equal(await getHomeRole('home-1', 'member-1'), null);

  ownerIsPaid = true;
  assert.equal(await getHomeRole('home-1', 'member-1'), 'editor');
});
