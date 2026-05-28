import test from 'node:test';
import assert from 'node:assert/strict';
import {
  HomeNameSchema,
  HomeSchema,
  InviteSchema,
  AppStoreTransactionSyncSchema,
  ManualEntitlementGrantSchema,
  ItemSchema,
  LocationSchema,
  MemberRoleSchema,
  UpdateMemberRoleSchema,
} from '../src/lib/schemas';

test('home name schema enforces non-empty names up to 100 chars', () => {
  assert.equal(HomeNameSchema.parse({ name: '33 Stratton Sq' }).name, '33 Stratton Sq');
  assert.throws(() => HomeNameSchema.parse({ name: '' }));
  assert.throws(() => HomeNameSchema.parse({ name: 'x'.repeat(101) }));
});

test('home schema accepts icons and flags', () => {
  assert.deepEqual(
    HomeSchema.parse({ name: '145 Lex', icon: 'house.fill', is_flagged: false }),
    { name: '145 Lex', icon: 'house.fill', is_flagged: false }
  );
  assert.throws(() => HomeSchema.parse({ name: '145 Lex', icon: '' }));
});

test('app store transaction sync schema accepts snake and camel case payloads', () => {
  assert.deepEqual(
    AppStoreTransactionSyncSchema.parse({ signed_transaction_info: 'signed-jws' }),
    { signed_transaction_info: 'signed-jws' }
  );
  assert.deepEqual(
    AppStoreTransactionSyncSchema.parse({ signedTransactionInfo: 'signed-jws' }),
    { signed_transaction_info: 'signed-jws' }
  );
  assert.throws(() => AppStoreTransactionSyncSchema.parse({ signed_transaction_info: '' }));
});

test('manual entitlement grant schema normalizes email and supported sources', () => {
  assert.deepEqual(
    ManualEntitlementGrantSchema.parse({ email: ' Person@Example.com ' }),
    { email: 'person@example.com', source: 'manual' }
  );
  assert.deepEqual(
    ManualEntitlementGrantSchema.parse({
      email: 'person@example.com',
      source: 'promo',
      expires_at: '2026-06-01T00:00:00.000Z',
    }),
    { email: 'person@example.com', source: 'promo', expires_at: '2026-06-01T00:00:00.000Z' }
  );
  assert.throws(() => ManualEntitlementGrantSchema.parse({ email: 'person@example.com', source: 'app_store' }));
});

test('member invite schemas accept supported roles and valid emails only', () => {
  assert.equal(MemberRoleSchema.parse('admin'), 'admin');
  assert.equal(MemberRoleSchema.parse('editor'), 'editor');
  assert.equal(MemberRoleSchema.parse('viewer'), 'viewer');
  assert.deepEqual(
    InviteSchema.parse({ email: 'person@example.com', role: 'editor' }),
    { email: 'person@example.com', role: 'editor' }
  );
  assert.deepEqual(
    InviteSchema.parse({ email: ' Person@Example.com ', role: 'viewer' }),
    { email: 'person@example.com', role: 'viewer' }
  );
  assert.deepEqual(UpdateMemberRoleSchema.parse({ role: 'viewer' }), { role: 'viewer' });

  assert.throws(() => MemberRoleSchema.parse('owner'));
  assert.throws(() => InviteSchema.parse({ email: 'not-an-email', role: 'editor' }));
  assert.throws(() => UpdateMemberRoleSchema.parse({ role: 'owner' }));
});

test('location schema validates parent ids and sort order', () => {
  const id = '7c5b9f9b-44bd-4cea-8ef2-17490c9d42a6';

  const parsed = LocationSchema.parse({
    name: 'Living Room',
    parent_id: id,
    type: 'room',
    sort_order: 2,
    icon: 'sofa.fill',
  });
  assert.equal(parsed.parent_id, id);
  assert.equal(parsed.icon, 'sofa.fill');

  assert.equal(LocationSchema.parse({
    name: 'Top Floor',
    parent_id: null,
    type: 'floor',
  }).parent_id, null);

  assert.throws(() => LocationSchema.parse({ name: 'Room', parent_id: 'bad-id', type: 'room' }));
  assert.throws(() => LocationSchema.parse({ name: 'Room', type: 'room', sort_order: 1.5 }));
});

test('item schema rejects invalid quantities and urls', () => {
  const parsed = ItemSchema.parse({
    name: 'Keys',
    quantity: 1,
    icon: 'key.fill',
    purchase_date: '2026-05-24',
    serial_number: 'SN-123',
    model_number: 'MX-1',
    warranty_expires_date: '2027-05-24',
    estimated_value_cents: 12999,
    is_flagged: false,
  });
  assert.equal(parsed.quantity, 1);
  assert.equal(parsed.icon, 'key.fill');
  assert.equal(parsed.serial_number, 'SN-123');
  assert.equal(parsed.model_number, 'MX-1');
  assert.equal(parsed.warranty_expires_date, '2027-05-24');
  assert.equal(parsed.estimated_value_cents, 12999);
  assert.equal(parsed.is_flagged, false);

  assert.throws(() => ItemSchema.parse({ name: 'Keys', quantity: 0 }));
  assert.throws(() => ItemSchema.parse({ name: 'Keys', quantity: 1.5 }));
  assert.throws(() => ItemSchema.parse({ name: 'Keys', photo_urls: ['not-a-url'] }));
  assert.throws(() => ItemSchema.parse({ name: 'Keys', properties: [{ id: 'prop-1', key: '', value: 'Brass' }] }));
  assert.throws(() => ItemSchema.parse({ name: 'Keys', icon: '' }));
  assert.throws(() => ItemSchema.parse({ name: 'Keys', purchase_date: '05/24/2026' }));
  assert.throws(() => ItemSchema.parse({ name: 'Keys', estimated_value_cents: -1 }));
});

test('item schema accepts generated S3 object keys as document ids', () => {
  const key = [
    'homes',
    'b59688f2-4dbf-468c-995d-5332260ea096',
    'items',
    'documents',
    '7a8560c4-d0dc-4f46-a5a3-22ac0a50685d-Untitled.png-B00B638F-07C2-47B1-9B3D-7C2764286D76.png',
  ].join('/');

  const parsed = ItemSchema.parse({
    name: 'Manual',
    documents: [
      {
        id: key,
        url: `https://cdn.example.com/${key}`,
        name: 'Untitled.png B00B638F-07C2-47B1-9B3D-7C2764286D76.png',
        content_type: 'image/png',
      },
    ],
  });

  assert.equal(parsed.documents?.[0]?.id, key);
});
