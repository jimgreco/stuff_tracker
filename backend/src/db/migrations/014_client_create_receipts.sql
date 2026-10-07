-- Effect receipts are separate from activity metadata and have no retention TTL.
-- A deletion/cancel keeps its receipt so an old POST cannot recreate the entity.
CREATE TABLE client_create_receipts (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('home', 'location', 'item')),
  client_id UUID NOT NULL,
  home_id UUID,
  request_hash TEXT,
  resource_id UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, entity_type, client_id),
  CHECK (resource_id = client_id),
  CHECK (request_hash IS NOT NULL OR deleted_at IS NOT NULL)
);
CREATE INDEX client_create_receipts_resource ON client_create_receipts (entity_type, resource_id);

CREATE FUNCTION retire_client_create_receipt() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  UPDATE client_create_receipts SET deleted_at = COALESCE(deleted_at, NOW())
  WHERE entity_type = TG_ARGV[0] AND resource_id = OLD.id;
  RETURN OLD;
END;
$$;
CREATE TRIGGER retire_home_create AFTER DELETE ON homes
  FOR EACH ROW EXECUTE FUNCTION retire_client_create_receipt('home');
CREATE TRIGGER retire_location_create AFTER DELETE ON locations
  FOR EACH ROW EXECUTE FUNCTION retire_client_create_receipt('location');
CREATE TRIGGER retire_item_create AFTER DELETE ON items
  FOR EACH ROW EXECUTE FUNCTION retire_client_create_receipt('item');
