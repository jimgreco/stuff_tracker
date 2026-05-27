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
  serial_number TEXT,
  model_number TEXT,
  warranty_expires_date DATE,
  estimated_value_cents INTEGER,
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
ALTER TABLE items ADD COLUMN IF NOT EXISTS serial_number TEXT;
ALTER TABLE items ADD COLUMN IF NOT EXISTS model_number TEXT;
ALTER TABLE items ADD COLUMN IF NOT EXISTS warranty_expires_date DATE;
ALTER TABLE items ADD COLUMN IF NOT EXISTS estimated_value_cents INTEGER;
ALTER TABLE users ADD COLUMN IF NOT EXISTS tokens_revoked_before TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS auth_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  refresh_token_hash TEXT UNIQUE,
  refresh_token_expires_at TIMESTAMPTZ,
  user_agent TEXT,
  ip_address TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS user_entitlements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  source TEXT NOT NULL CHECK (source IN ('app_store', 'manual', 'promo', 'admin')),
  status TEXT NOT NULL CHECK (status IN ('active', 'expired', 'revoked')),
  product_id TEXT,
  transaction_id TEXT,
  original_transaction_id TEXT,
  app_store_environment TEXT,
  expires_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS app_store_transactions (
  transaction_id TEXT PRIMARY KEY,
  original_transaction_id TEXT NOT NULL,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  product_id TEXT NOT NULL,
  environment TEXT NOT NULL,
  purchase_date TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  revocation_date TIMESTAMPTZ,
  signed_transaction_info TEXT NOT NULL,
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE items DROP CONSTRAINT IF EXISTS items_estimated_value_cents_check;
ALTER TABLE items
  ADD CONSTRAINT items_estimated_value_cents_check
  CHECK (estimated_value_cents IS NULL OR estimated_value_cents >= 0);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_locations_home_id ON locations(home_id);
CREATE INDEX IF NOT EXISTS idx_locations_parent_id ON locations(parent_id);
CREATE INDEX IF NOT EXISTS idx_items_home_id ON items(home_id);
CREATE INDEX IF NOT EXISTS idx_items_location_id ON items(location_id);
CREATE INDEX IF NOT EXISTS idx_home_members_user_id ON home_members(user_id);
CREATE INDEX IF NOT EXISTS idx_auth_sessions_user_id ON auth_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_auth_sessions_active_user_id
  ON auth_sessions(user_id)
  WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_auth_sessions_refresh_token_hash
  ON auth_sessions(refresh_token_hash)
  WHERE revoked_at IS NULL AND refresh_token_hash IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_entitlements_app_store_original_transaction
  ON user_entitlements (source, original_transaction_id)
  WHERE source = 'app_store' AND original_transaction_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_user_entitlements_user_active
  ON user_entitlements (user_id, status, expires_at)
  WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_app_store_transactions_original_transaction
  ON app_store_transactions (original_transaction_id);

-- Full-text search index on items
CREATE INDEX IF NOT EXISTS idx_items_search ON items USING GIN (
  to_tsvector(
    'english',
    name || ' ' ||
    COALESCE(notes, '') || ' ' ||
    COALESCE(properties::text, '') || ' ' ||
    COALESCE(serial_number, '') || ' ' ||
    COALESCE(model_number, '')
  )
);
