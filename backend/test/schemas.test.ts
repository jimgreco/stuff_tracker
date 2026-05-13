import test from 'node:test';
import assert from 'node:assert/strict';
import {
  HomeNameSchema,
  InviteSchema,
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

  assert.equal(LocationSchema.parse({
    name: 'Living Room',
    parent_id: id,
    type: 'room',
    sort_order: 2,
  }).parent_id, id);

  assert.equal(LocationSchema.parse({
    name: 'Top Floor',
    parent_id: null,
    type: 'floor',
  }).parent_id, null);

  assert.throws(() => LocationSchema.parse({ name: 'Room', parent_id: 'bad-id', type: 'room' }));
  assert.throws(() => LocationSchema.parse({ name: 'Room', type: 'room', sort_order: 1.5 }));
});

test('item schema rejects invalid quantities and urls', () => {
  assert.equal(ItemSchema.parse({ name: 'Keys', quantity: 1 }).quantity, 1);

  assert.throws(() => ItemSchema.parse({ name: 'Keys', quantity: 0 }));
  assert.throws(() => ItemSchema.parse({ name: 'Keys', quantity: 1.5 }));
  assert.throws(() => ItemSchema.parse({ name: 'Keys', photo_url: 'not-a-url' }));
});
