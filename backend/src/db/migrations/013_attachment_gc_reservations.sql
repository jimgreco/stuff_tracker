-- Persistent no-adoption reservations close the DB/S3 check-to-delete race.
-- Rows are deliberately retained after success or failure: S3 results/timeouts
-- cannot be rolled back with a database transaction. Retry cleanup is idempotent.
CREATE TABLE attachment_gc_tombstones (
    object_key TEXT PRIMARY KEY,
    reserved_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);
