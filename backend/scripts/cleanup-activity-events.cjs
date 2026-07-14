require('dotenv').config();
const { Pool } = require('pg');

const retentionDays = Math.max(Number(process.env.ACTIVITY_RETENTION_DAYS) || 365, 30);
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.PGSSL === 'true' ? { rejectUnauthorized: false } : false,
});

pool.query(
  `DELETE FROM home_activity_events
   WHERE created_at < NOW() - ($1 * INTERVAL '1 day')`,
  [retentionDays]
).then(({ rowCount }) => {
  console.log(`Removed ${rowCount ?? 0} activity events older than ${retentionDays} days.`);
}).catch((error) => {
  console.error('Activity cleanup failed:', error instanceof Error ? error.message : error);
  process.exitCode = 1;
}).finally(() => pool.end());
