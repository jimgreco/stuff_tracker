CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Users
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  avatar_url TEXT,
  google_id TEXT UNIQUE,
  apple_id TEXT UNIQUE,
  tokens_revoked_before TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Homes (top-level location)
CREATE TABLE IF NOT EXISTS homes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  icon TEXT,
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Home members (sharing)
CREATE TABLE IF NOT EXISTS home_members (
  home_id UUID NOT NULL REFERENCES homes(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('admin', 'editor', 'viewer')),
  invited_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (home_id, user_id)
);

-- Locations: rooms, containers, nested containers — all in one self-referencing table
-- type: 'room' (child of home), 'container' (child of room or container)
CREATE TABLE IF NOT EXISTS locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  home_id UUID NOT NULL REFERENCES homes(id) ON DELETE CASCADE,
  parent_id UUID REFERENCES locations(id) ON DELETE CASCADE, -- NULL means direct child of home (i.e. a room)
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('floor', 'room', 'container')),
  sort_order INTEGER NOT NULL DEFAULT 0,
  icon TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Items (stuff)
CREATE TABLE IF NOT EXISTS items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  home_id UUID NOT NULL REFERENCES homes(id) ON DELETE CASCADE,
  location_id UUID REFERENCES locations(id) ON DELETE SET NULL, -- NULL means "in the home directly"
  name TEXT NOT NULL,
  icon TEXT,
  notes TEXT,
  quantity INTEGER NOT NULL DEFAULT 1,
  photo_url TEXT,
  photo_urls TEXT[] NOT NULL DEFAULT '{}',
  document_url TEXT,
  document_name TEXT,
  document_content_type TEXT,
  properties JSONB NOT NULL DEFAULT '[]'::jsonb,
  documents JSONB NOT NULL DEFAULT '[]'::jsonb,
  purchase_date DATE,
  created_by UUID NOT NULL REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE items DROP COLUMN IF EXISTS tags;
ALTER TABLE homes ADD COLUMN IF NOT EXISTS icon TEXT;
ALTER TABLE locations ADD COLUMN IF NOT EXISTS icon TEXT;
ALTER TABLE items ADD COLUMN IF NOT EXISTS icon TEXT;
ALTER TABLE items ADD COLUMN IF NOT EXISTS photo_urls TEXT[] NOT NULL DEFAULT '{}';
ALTER TABLE items ADD COLUMN IF NOT EXISTS document_url TEXT;
ALTER TABLE items ADD COLUMN IF NOT EXISTS document_name TEXT;
ALTER TABLE items ADD COLUMN IF NOT EXISTS document_content_type TEXT;
ALTER TABLE items ADD COLUMN IF NOT EXISTS properties JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE items ADD COLUMN IF NOT EXISTS documents JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE users ADD COLUMN IF NOT EXISTS tokens_revoked_before TIMESTAMPTZ;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_locations_home_id ON locations(home_id);
CREATE INDEX IF NOT EXISTS idx_locations_parent_id ON locations(parent_id);
CREATE INDEX IF NOT EXISTS idx_items_home_id ON items(home_id);
CREATE INDEX IF NOT EXISTS idx_items_location_id ON items(location_id);
CREATE INDEX IF NOT EXISTS idx_home_members_user_id ON home_members(user_id);

-- Full-text search index on items
CREATE INDEX IF NOT EXISTS idx_items_search ON items USING GIN (to_tsvector('english', name || ' ' || COALESCE(notes, '')));
