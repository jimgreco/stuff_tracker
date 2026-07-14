-- Append-only audit history for shared homes. Rows intentionally do not reference
-- homes or entities with foreign keys so deletion cannot erase their history.
CREATE TABLE IF NOT EXISTS home_activity_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  home_id UUID NOT NULL,
  actor_id UUID,
  actor_name TEXT,
  actor_email TEXT,
  action TEXT NOT NULL CHECK (action IN (
    'created', 'updated', 'moved', 'reordered', 'flagged', 'unflagged',
    'deleted', 'member_added', 'member_role_changed', 'member_removed'
  )),
  entity_type TEXT NOT NULL CHECK (entity_type IN ('home', 'location', 'item', 'member')),
  entity_id UUID,
  entity_name TEXT NOT NULL,
  location_path TEXT,
  summary TEXT NOT NULL,
  changes JSONB NOT NULL DEFAULT '[]'::jsonb,
  mutation_id TEXT,
  event_scope TEXT NOT NULL,
  client_occurred_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_home_activity_feed
  ON home_activity_events (home_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_home_activity_entity
  ON home_activity_events (home_id, entity_type, entity_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_home_activity_actor
  ON home_activity_events (home_id, actor_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_home_activity_mutation
  ON home_activity_events (actor_id, mutation_id, event_scope)
  WHERE mutation_id IS NOT NULL;

CREATE OR REPLACE FUNCTION record_home_activity() RETURNS TRIGGER AS $$
DECLARE
  old_row JSONB := CASE WHEN TG_OP = 'INSERT' THEN '{}'::jsonb ELSE to_jsonb(OLD) END;
  new_row JSONB := CASE WHEN TG_OP = 'DELETE' THEN '{}'::jsonb ELSE to_jsonb(NEW) END;
  row_data JSONB := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  activity_home_id UUID;
  previous_home_id UUID;
  activity_actor_id UUID;
  activity_actor_name TEXT;
  activity_actor_email TEXT;
  activity_action TEXT;
  activity_entity_type TEXT;
  activity_entity_id UUID;
  activity_entity_name TEXT;
  activity_location_path TEXT;
  previous_location_path TEXT;
  activity_summary TEXT;
  activity_changes JSONB := '[]'::jsonb;
  activity_mutation_id TEXT := NULLIF(current_setting('app.activity_mutation_id', true), '');
  activity_occurred_at TIMESTAMPTZ;
  field_name TEXT;
  before_value JSONB;
  after_value JSONB;
BEGIN
  activity_actor_id := NULLIF(current_setting('app.activity_actor_id', true), '')::uuid;
  activity_occurred_at := NULLIF(current_setting('app.activity_occurred_at', true), '')::timestamptz;
  SELECT name, email INTO activity_actor_name, activity_actor_email FROM users WHERE id = activity_actor_id;

  IF TG_TABLE_NAME = 'homes' THEN
    activity_entity_type := 'home';
    activity_home_id := (row_data->>'id')::uuid;
    activity_entity_id := activity_home_id;
    activity_entity_name := COALESCE(row_data->>'name', 'Deleted home');
  ELSIF TG_TABLE_NAME = 'locations' THEN
    activity_entity_type := 'location';
    activity_home_id := (row_data->>'home_id')::uuid;
    previous_home_id := NULLIF(old_row->>'home_id', '')::uuid;
    activity_entity_id := (row_data->>'id')::uuid;
    activity_entity_name := COALESCE(row_data->>'name', 'Deleted location');
    WITH RECURSIVE ancestors AS (
      SELECT id, parent_id, name, 0 AS depth FROM locations WHERE id = activity_entity_id
      UNION ALL
      SELECT l.id, l.parent_id, l.name, a.depth + 1 FROM locations l JOIN ancestors a ON a.parent_id = l.id
    ) SELECT string_agg(name, ' / ' ORDER BY depth DESC) INTO activity_location_path FROM ancestors;
    IF TG_OP <> 'INSERT' THEN
      WITH RECURSIVE ancestors AS (
        SELECT id, parent_id, name, 0 AS depth FROM locations WHERE id = NULLIF(old_row->>'parent_id', '')::uuid
        UNION ALL
        SELECT l.id, l.parent_id, l.name, a.depth + 1 FROM locations l JOIN ancestors a ON a.parent_id = l.id
      ) SELECT concat_ws(' / ', string_agg(name, ' / ' ORDER BY depth DESC), old_row->>'name')
        INTO previous_location_path FROM ancestors;
      previous_location_path := COALESCE(previous_location_path, old_row->>'name');
      IF TG_OP = 'DELETE' THEN activity_location_path := previous_location_path; END IF;
    END IF;
  ELSIF TG_TABLE_NAME = 'items' THEN
    activity_entity_type := 'item';
    activity_home_id := (row_data->>'home_id')::uuid;
    previous_home_id := NULLIF(old_row->>'home_id', '')::uuid;
    activity_entity_id := (row_data->>'id')::uuid;
    activity_entity_name := COALESCE(row_data->>'name', 'Deleted item');
    WITH RECURSIVE ancestors AS (
      SELECT id, parent_id, name, 0 AS depth FROM locations WHERE id = NULLIF(row_data->>'location_id', '')::uuid
      UNION ALL
      SELECT l.id, l.parent_id, l.name, a.depth + 1 FROM locations l JOIN ancestors a ON a.parent_id = l.id
    ) SELECT string_agg(name, ' / ' ORDER BY depth DESC) INTO activity_location_path FROM ancestors;
    IF TG_OP <> 'INSERT' THEN
      WITH RECURSIVE ancestors AS (
        SELECT id, parent_id, name, 0 AS depth FROM locations WHERE id = NULLIF(old_row->>'location_id', '')::uuid
        UNION ALL
        SELECT l.id, l.parent_id, l.name, a.depth + 1 FROM locations l JOIN ancestors a ON a.parent_id = l.id
      ) SELECT string_agg(name, ' / ' ORDER BY depth DESC) INTO previous_location_path FROM ancestors;
    END IF;
  ELSE
    activity_entity_type := 'member';
    activity_home_id := (row_data->>'home_id')::uuid;
    activity_entity_id := (row_data->>'user_id')::uuid;
    SELECT COALESCE(name, email) INTO activity_entity_name
      FROM users WHERE id = activity_entity_id;
    activity_entity_name := COALESCE(activity_entity_name, 'Former member');
  END IF;

  IF TG_OP = 'INSERT' THEN
    activity_action := CASE WHEN TG_TABLE_NAME = 'home_members' THEN 'member_added' ELSE 'created' END;
  ELSIF TG_OP = 'DELETE' THEN
    activity_action := CASE WHEN TG_TABLE_NAME = 'home_members' THEN 'member_removed' ELSE 'deleted' END;
  ELSIF TG_TABLE_NAME = 'home_members' THEN
    activity_action := 'member_role_changed';
  ELSIF old_row->'is_flagged' IS DISTINCT FROM new_row->'is_flagged' THEN
    activity_action := CASE WHEN (new_row->>'is_flagged')::boolean THEN 'flagged' ELSE 'unflagged' END;
  ELSIF old_row->'home_id' IS DISTINCT FROM new_row->'home_id'
     OR old_row->'location_id' IS DISTINCT FROM new_row->'location_id'
     OR old_row->'parent_id' IS DISTINCT FROM new_row->'parent_id' THEN
    activity_action := 'moved';
  ELSIF old_row->'sort_order' IS DISTINCT FROM new_row->'sort_order' THEN
    activity_action := 'reordered';
  ELSE
    activity_action := 'updated';
  END IF;

  -- Only retain deliberately safe field values. Attachments are represented by
  -- counts; notes, properties, serial/model values and storage URLs never enter history.
  FOREACH field_name IN ARRAY (
    CASE activity_entity_type
      WHEN 'home' THEN ARRAY['name', 'icon', 'is_flagged']
      WHEN 'location' THEN ARRAY['name', 'type', 'sort_order', 'icon', 'is_flagged']
      WHEN 'item' THEN ARRAY['name', 'quantity', 'purchase_date', 'warranty_expires_date', 'estimated_value_cents', 'is_flagged', 'sort_order']
      ELSE ARRAY['role']
    END
  ) LOOP
    before_value := old_row->field_name;
    after_value := new_row->field_name;
    IF before_value IS DISTINCT FROM after_value THEN
      activity_changes := activity_changes || jsonb_build_array(jsonb_build_object(
        'field', field_name, 'before', before_value, 'after', after_value
      ));
    END IF;
  END LOOP;

  IF activity_entity_type = 'item' AND TG_OP = 'UPDATE' THEN
    IF jsonb_array_length(COALESCE(old_row->'photo_urls', '[]'::jsonb)) IS DISTINCT FROM jsonb_array_length(COALESCE(new_row->'photo_urls', '[]'::jsonb)) THEN
      activity_changes := activity_changes || jsonb_build_array(jsonb_build_object('field', 'photos', 'before', jsonb_array_length(COALESCE(old_row->'photo_urls', '[]'::jsonb)), 'after', jsonb_array_length(COALESCE(new_row->'photo_urls', '[]'::jsonb))));
    END IF;
    IF jsonb_array_length(COALESCE(old_row->'documents', '[]'::jsonb)) IS DISTINCT FROM jsonb_array_length(COALESCE(new_row->'documents', '[]'::jsonb)) THEN
      activity_changes := activity_changes || jsonb_build_array(jsonb_build_object('field', 'documents', 'before', jsonb_array_length(COALESCE(old_row->'documents', '[]'::jsonb)), 'after', jsonb_array_length(COALESCE(new_row->'documents', '[]'::jsonb))));
    END IF;
    IF old_row->'notes' IS DISTINCT FROM new_row->'notes' THEN activity_changes := activity_changes || '[{"field":"notes"}]'::jsonb; END IF;
    IF old_row->'properties' IS DISTINCT FROM new_row->'properties' THEN activity_changes := activity_changes || '[{"field":"properties"}]'::jsonb; END IF;
    IF old_row->'serial_number' IS DISTINCT FROM new_row->'serial_number' THEN activity_changes := activity_changes || '[{"field":"serial number"}]'::jsonb; END IF;
    IF old_row->'model_number' IS DISTINCT FROM new_row->'model_number' THEN activity_changes := activity_changes || '[{"field":"model number"}]'::jsonb; END IF;
  END IF;

  IF activity_action = 'moved' AND previous_location_path IS DISTINCT FROM activity_location_path THEN
    activity_changes := activity_changes || jsonb_build_array(jsonb_build_object(
      'field', 'location', 'before', previous_location_path, 'after', activity_location_path
    ));
  END IF;

  activity_summary := CASE activity_action
    WHEN 'created' THEN 'Created ' || activity_entity_name
    WHEN 'updated' THEN 'Updated ' || activity_entity_name
    WHEN 'moved' THEN 'Moved ' || activity_entity_name || COALESCE(' to ' || activity_location_path, '')
    WHEN 'reordered' THEN 'Reordered ' || activity_entity_name
    WHEN 'flagged' THEN 'Flagged ' || activity_entity_name
    WHEN 'unflagged' THEN 'Unflagged ' || activity_entity_name
    WHEN 'deleted' THEN 'Deleted ' || activity_entity_name
    WHEN 'member_added' THEN 'Added ' || activity_entity_name
    WHEN 'member_role_changed' THEN 'Changed ' || activity_entity_name || '''s role'
    WHEN 'member_removed' THEN 'Removed ' || activity_entity_name
  END;

  INSERT INTO home_activity_events (
    home_id, actor_id, actor_name, actor_email, action, entity_type, entity_id,
    entity_name, location_path, summary, changes, mutation_id, event_scope, client_occurred_at
  ) VALUES (
    activity_home_id, activity_actor_id, activity_actor_name, activity_actor_email,
    activity_action, activity_entity_type, activity_entity_id, activity_entity_name,
    activity_location_path, activity_summary, activity_changes, activity_mutation_id,
    TG_TABLE_NAME || ':' || activity_entity_id || ':' || TG_OP || ':' || activity_home_id,
    activity_occurred_at
  ) ON CONFLICT DO NOTHING;

  IF TG_OP = 'UPDATE' AND previous_home_id IS NOT NULL AND previous_home_id <> activity_home_id THEN
    INSERT INTO home_activity_events (
      home_id, actor_id, actor_name, actor_email, action, entity_type, entity_id,
      entity_name, location_path, summary, changes, mutation_id, event_scope, client_occurred_at
    ) VALUES (
      previous_home_id, activity_actor_id, activity_actor_name, activity_actor_email,
      'moved', activity_entity_type, activity_entity_id, activity_entity_name,
      previous_location_path, 'Moved ' || activity_entity_name || COALESCE(' from ' || previous_location_path, ''), activity_changes, activity_mutation_id,
      TG_TABLE_NAME || ':' || activity_entity_id || ':MOVE_FROM:' || previous_home_id,
      activity_occurred_at
    ) ON CONFLICT DO NOTHING;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS homes_activity_trigger ON homes;
CREATE TRIGGER homes_activity_trigger AFTER INSERT OR UPDATE OR DELETE ON homes
  FOR EACH ROW EXECUTE FUNCTION record_home_activity();
DROP TRIGGER IF EXISTS locations_activity_trigger ON locations;
CREATE TRIGGER locations_activity_trigger AFTER INSERT OR UPDATE OR DELETE ON locations
  FOR EACH ROW EXECUTE FUNCTION record_home_activity();
DROP TRIGGER IF EXISTS items_activity_trigger ON items;
CREATE TRIGGER items_activity_trigger AFTER INSERT OR UPDATE OR DELETE ON items
  FOR EACH ROW EXECUTE FUNCTION record_home_activity();
DROP TRIGGER IF EXISTS home_members_activity_trigger ON home_members;
CREATE TRIGGER home_members_activity_trigger AFTER INSERT OR UPDATE OR DELETE ON home_members
  FOR EACH ROW EXECUTE FUNCTION record_home_activity();

COMMENT ON TABLE home_activity_events IS
  'Append-only shared-home activity retained for 365 days. Run activity:cleanup daily.';
