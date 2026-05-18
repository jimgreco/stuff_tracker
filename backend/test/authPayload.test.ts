import test from 'node:test';
import assert from 'node:assert/strict';
import { readAppleFullName, readAuthString } from '../src/lib/authPayload';

test('auth token reader accepts camelCase and snake_case body fields', () => {
  assert.equal(readAuthString({ idToken: 'google-token' }, 'idToken', 'id_token'), 'google-token');
  assert.equal(readAuthString({ id_token: 'google-token' }, 'idToken', 'id_token'), 'google-token');
  assert.equal(readAuthString({ identityToken: 'apple-token' }, 'identityToken', 'identity_token'), 'apple-token');
  assert.equal(readAuthString({ identity_token: 'apple-token' }, 'identityToken', 'identity_token'), 'apple-token');
  assert.equal(readAuthString({ identityToken: '' }, 'identityToken', 'identity_token'), undefined);
});

test('Apple full name reader accepts camelCase and snake_case body fields', () => {
  assert.deepEqual(
    readAppleFullName({ fullName: { givenName: 'Jane', familyName: 'Appleseed' } }),
    { givenName: 'Jane', familyName: 'Appleseed' }
  );

  assert.deepEqual(
    readAppleFullName({ full_name: { given_name: 'Jane', family_name: 'Appleseed' } }),
    { givenName: 'Jane', familyName: 'Appleseed' }
  );

  assert.equal(readAppleFullName({ fullName: {} }), undefined);
});
