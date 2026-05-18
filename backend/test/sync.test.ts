import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { LOCATION_TYPES, locationTypeConstraintSql } from '../src/db/locationTypeConstraint';
import { ItemSchema, ItemUploadSchema, LocationSchema } from '../src/lib/schemas';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const backendRoot = path.resolve(__dirname, '..');

test('location sync validation accepts floor locations', () => {
  const parsed = LocationSchema.parse({
    name: 'Top Floor',
    parent_id: null,
    type: 'floor',
    sort_order: 0,
    icon: 'building.2',
  });

  assert.equal(parsed.type, 'floor');
  assert.equal(parsed.icon, 'building.2');
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
    icon: 'sofa.fill',
    notes: null,
    quantity: 1,
  });

  assert.equal(parsed.location_id, null);
  assert.equal(parsed.name, 'Couch 5');
  assert.equal(parsed.icon, 'sofa.fill');
});

test('item validation keeps ordered properties and document metadata', () => {
  const parsed = ItemSchema.parse({
    name: 'Warranty folder',
    properties: [
      { id: 'prop-1', key: 'Location', value: 'Garage' },
      { id: 'prop-2', key: 'Category', value: 'Tools' },
      { id: 'prop-3', key: 'Receipt', value: 'Yes' },
    ],
    photo_urls: ['https://cdn.example.com/chair-front.jpg', 'https://cdn.example.com/chair-side.jpg'],
    documents: [
      {
        id: 'doc-1',
        url: 'https://cdn.example.com/manual.pdf',
        name: 'manual.pdf',
        content_type: 'application/pdf',
      },
      {
        id: 'doc-2',
        url: 'https://cdn.example.com/receipt.jpg',
        name: 'receipt.jpg',
        content_type: 'image/jpeg',
      },
    ],
  });

  assert.deepEqual(parsed.properties?.map(({ key, value }) => [key, value]), [
    ['Location', 'Garage'],
    ['Category', 'Tools'],
    ['Receipt', 'Yes'],
  ]);
  assert.deepEqual(parsed.photo_urls, [
    'https://cdn.example.com/chair-front.jpg',
    'https://cdn.example.com/chair-side.jpg',
  ]);
  assert.equal(parsed.documents?.length, 2);
});

test('item upload validation accepts photos and documents', () => {
  assert.equal(ItemUploadSchema.parse({
    kind: 'photo',
    file_name: 'chair.jpg',
    content_type: 'image/jpeg',
    size_bytes: 1024,
  }).kind, 'photo');

  assert.equal(ItemUploadSchema.parse({
    kind: 'document',
    file_name: 'manual.pdf',
    content_type: 'application/pdf',
    size_bytes: 2048,
  }).kind, 'document');

  assert.throws(() => ItemUploadSchema.parse({
    kind: 'photo',
    file_name: 'chair.jpg',
    content_type: 'image/jpeg',
    size_bytes: 0,
  }));
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

  assert.match(schemaSql, /CREATE EXTENSION IF NOT EXISTS pgcrypto/);
  assert.match(schemaSql, /type IN \('floor', 'room', 'container'\)/);
  assert.match(schemaSql, /ALTER TABLE homes ADD COLUMN IF NOT EXISTS icon TEXT/);
  assert.match(schemaSql, /ALTER TABLE locations ADD COLUMN IF NOT EXISTS icon TEXT/);
  assert.match(schemaSql, /ALTER TABLE items ADD COLUMN IF NOT EXISTS icon TEXT/);
});
