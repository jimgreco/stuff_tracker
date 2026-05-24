ALTER TABLE items
  ADD COLUMN IF NOT EXISTS serial_number TEXT,
  ADD COLUMN IF NOT EXISTS model_number TEXT,
  ADD COLUMN IF NOT EXISTS warranty_expires_date DATE,
  ADD COLUMN IF NOT EXISTS estimated_value_cents INTEGER;

ALTER TABLE items
  DROP CONSTRAINT IF EXISTS items_estimated_value_cents_check;

ALTER TABLE items
  ADD CONSTRAINT items_estimated_value_cents_check
  CHECK (estimated_value_cents IS NULL OR estimated_value_cents >= 0);

DROP INDEX IF EXISTS idx_items_search;

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
