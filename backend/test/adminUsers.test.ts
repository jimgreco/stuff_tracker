import test from 'node:test';
import assert from 'node:assert/strict';
import { isAdminEmail } from '../src/lib/adminUsers';

const originalStuffAdminEmails = process.env.STUFF_ADMIN_EMAILS;

test.afterEach(() => {
  restoreEnv('STUFF_ADMIN_EMAILS', originalStuffAdminEmails);
});

test('isAdminEmail accepts configured admin emails case-insensitively', () => {
  process.env.STUFF_ADMIN_EMAILS = 'owner@example.com, Admin@Example.com ';

  assert.equal(isAdminEmail('admin@example.com'), true);
  assert.equal(isAdminEmail(' OWNER@example.com '), true);
  assert.equal(isAdminEmail('person@example.com'), false);
});

function restoreEnv(key: string, value: string | undefined) {
  if (value === undefined) {
    delete process.env[key];
  } else {
    process.env[key] = value;
  }
}
