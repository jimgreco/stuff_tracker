#!/usr/bin/env node
const { Pool } = require('pg');

async function main() {
  const expectedRole = process.env.DB_EXPECTED_APP_ROLE?.trim();
  const requireSsl = truthy(process.env.DB_REQUIRE_SSL);
  const pool = new Pool({ connectionString: requiredEnv('DATABASE_URL') });

  try {
    const { rows } = await pool.query(`
      SELECT
        current_user AS current_user,
        current_database() AS current_database,
        current_setting('ssl') AS ssl
    `);
    const row = rows[0];

    console.log(`Database user: ${row.current_user}`);
    console.log(`Database name: ${row.current_database}`);
    console.log(`Database SSL setting: ${row.ssl}`);

    if (expectedRole && row.current_user !== expectedRole) {
      throw new Error(`Expected app database role ${expectedRole}, got ${row.current_user}`);
    }

    if (['admin', 'postgres'].includes(row.current_user)) {
      throw new Error(`App is connected with privileged database role ${row.current_user}`);
    }

    if (requireSsl && row.ssl !== 'on') {
      throw new Error('Database SSL is not enabled');
    }

    console.log('database runtime hardening check passed');
  } finally {
    await pool.end();
  }
}

function requiredEnv(name) {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`${name} is required`);
  }
  return value;
}

function truthy(value) {
  return ['1', 'true', 'yes', 'on'].includes(String(value ?? '').trim().toLowerCase());
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exitCode = 1;
});
