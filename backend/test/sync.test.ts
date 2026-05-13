import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { LOCATION_TYPES, locationTypeConstraintSql } from '../src/db/locationTypeConstraint';
import { ItemSchema, LocationSchema } from '../src/lib/schemas';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const backendRoot = path.resolve(__dirname, '..');

test('location sync validation accepts floor locations', () => {
  const parsed = LocationSchema.parse({
    name: 'Top Floor',
    parent_id: null,
    type: 'floor',
    sort_order: 0,
  });

  assert.equal(parsed.type, 'floor');
});

test('location sync validation rejects unknown location types', () => {
  assert.throws(
    () => LocationSchema.parse({ name: 'Attic', type: 'level' }),
    /Invalid enum value/
  );
});

test('item sync validation allows missing legacy fields and explicit root location', () => {
  const parsed = ItemSchema.parse({
    name: 'Couch 5',
    location_id: null,
    notes: null,
    quantity: 1,
  });

  assert.equal(parsed.location_id, null);
  assert.equal(parsed.name, 'Couch 5');
});

test('location type migration constraint stays in sync with accepted schema values', () => {
  const sql = locationTypeConstraintSql();

  for (const type of LOCATION_TYPES) {
    assert.match(sql, new RegExp(`'${type}'`));
  }

  assert.match(sql, /DROP CONSTRAINT IF EXISTS locations_type_check/);
  assert.match(sql, /ADD CONSTRAINT locations_type_check/);
});

test('fresh database schema allows floor locations', () => {
  const schemaSql = fs.readFileSync(path.join(backendRoot, 'src/db/schema.sql'), 'utf8');

  assert.match(schemaSql, /type IN \('floor', 'room', 'container'\)/);
});
