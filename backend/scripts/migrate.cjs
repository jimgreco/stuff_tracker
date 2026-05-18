const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

require('dotenv').config();

const migrationsDir = [
  path.join(__dirname, '..', 'src', 'db', 'migrations'),
  path.join(__dirname, '..', 'dist', 'db', 'migrations'),
].find((candidate) => fs.existsSync(candidate));

if (!migrationsDir) {
  console.error('Migration failed: could not find migrations directory');
  process.exit(1);
}

async function migrate() {
  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: process.env.PGSSL === 'true' ? { rejectUnauthorized: false } : undefined,
  });
  const client = await pool.connect();

  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version TEXT PRIMARY KEY,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);

    const migrations = fs
      .readdirSync(migrationsDir)
      .filter((file) => file.endsWith('.sql'))
      .sort();

    for (const file of migrations) {
      const version = path.basename(file, '.sql');
      const applied = await client.query(
        'SELECT 1 FROM schema_migrations WHERE version = $1',
        [version]
      );
      if (applied.rows[0]) {
        continue;
      }

      await client.query('BEGIN');
      await client.query(fs.readFileSync(path.join(migrationsDir, file), 'utf8'));
      await client.query('INSERT INTO schema_migrations (version) VALUES ($1)', [version]);
      await client.query('COMMIT');
      console.log(`Applied migration ${version}`);
    }

    console.log('Migrations complete');
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch {}
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
