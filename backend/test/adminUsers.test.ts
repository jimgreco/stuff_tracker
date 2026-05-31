import test from 'node:test';
import assert from 'node:assert/strict';
import { isAdminEmail } from '../src/lib/adminUsers';

const originalStuffAdminEmails = process.env.STUFF_ADMIN_EMAILS;
const originalAdminEmails = process.env.ADMIN_EMAILS;

test.afterEach(() => {
  restoreEnv('STUFF_ADMIN_EMAILS', originalStuffAdminEmails);
  restoreEnv('ADMIN_EMAILS', originalAdminEmails);
});

test('isAdminEmail accepts configured admin emails case-insensitively', () => {
  process.env.STUFF_ADMIN_EMAILS = 'owner@example.com, Admin@Example.com ';
  delete process.env.ADMIN_EMAILS;

  assert.equal(isAdminEmail('admin@example.com'), true);
  assert.equal(isAdminEmail(' OWNER@example.com '), true);
  assert.equal(isAdminEmail('person@example.com'), false);
});

test('isAdminEmail supports legacy ADMIN_EMAILS fallback', () => {
  delete process.env.STUFF_ADMIN_EMAILS;
  process.env.ADMIN_EMAILS = 'fallback@example.com';

  assert.equal(isAdminEmail('fallback@example.com'), true);
});

function restoreEnv(key: string, value: string | undefined) {
  if (value === undefined) {
    delete process.env[key];
  } else {
    process.env[key] = value;
  }
}
