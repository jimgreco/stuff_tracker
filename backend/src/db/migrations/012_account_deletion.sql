-- Preserve items in someone else's shared home when their creator deletes an account.
ALTER TABLE items ALTER COLUMN created_by DROP NOT NULL;
ALTER TABLE items DROP CONSTRAINT items_created_by_fkey;
ALTER TABLE items ADD CONSTRAINT items_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL;

-- An invitation must not prevent its sender from deleting their account.
ALTER TABLE home_members DROP CONSTRAINT home_members_invited_by_fkey;
ALTER TABLE home_members ADD CONSTRAINT home_members_invited_by_fkey
  FOREIGN KEY (invited_by) REFERENCES users(id) ON DELETE SET NULL;
