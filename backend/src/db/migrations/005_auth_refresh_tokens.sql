ALTER TABLE auth_sessions ADD COLUMN IF NOT EXISTS refresh_token_hash TEXT UNIQUE;
ALTER TABLE auth_sessions ADD COLUMN IF NOT EXISTS refresh_token_expires_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_auth_sessions_refresh_token_hash
  ON auth_sessions(refresh_token_hash)
  WHERE revoked_at IS NULL AND refresh_token_hash IS NOT NULL;
