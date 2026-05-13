import test from 'node:test';
import assert from 'node:assert/strict';
import { canAdmin, canEdit } from '../src/lib/access';
import type { Role } from '../src/lib/access';

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
