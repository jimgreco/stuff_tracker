const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

require('dotenv').config();

const schemaPath = [
  path.join(__dirname, '..', 'src', 'db', 'schema.sql'),
  path.join(__dirname, '..', 'dist', 'db', 'schema.sql'),
].find((candidate) => fs.existsSync(candidate));

if (!schemaPath) {
  console.error('Migration failed: could not find schema.sql');
  process.exit(1);
}

const locationTypeConstraintSql = `
  ALTER TABLE locations DROP CONSTRAINT IF EXISTS locations_type_check;
  ALTER TABLE locations
    ADD CONSTRAINT locations_type_check
    CHECK (type IN ('floor', 'room', 'container'));
`;

async function migrate() {
  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: process.env.PGSSL === 'true' ? { rejectUnauthorized: false } : undefined,
  });
  const client = await pool.connect();

  try {
    await client.query('BEGIN');
    await client.query(fs.readFileSync(schemaPath, 'utf8'));
    await client.query(locationTypeConstraintSql);
    await client.query('COMMIT');
    console.log('Migration complete');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
    await pool.end();
  }
}

migrate().catch((err) => {
  console.error('Migration failed:', err);
  process.exit(1);
});
