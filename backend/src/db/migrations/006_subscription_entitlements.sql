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

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_entitlements_app_store_original_transaction
  ON user_entitlements (source, original_transaction_id)
  WHERE source = 'app_store' AND original_transaction_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_user_entitlements_user_active
  ON user_entitlements (user_id, status, expires_at)
  WHERE revoked_at IS NULL;

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

CREATE INDEX IF NOT EXISTS idx_app_store_transactions_original_transaction
  ON app_store_transactions (original_transaction_id);
