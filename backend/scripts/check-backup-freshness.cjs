const fs = require('fs');
const path = require('path');

require('dotenv').config();

const outputDir = process.env.DB_BACKUP_DIR || path.join(__dirname, '..', 'backups');
let maxAgeHours;
try {
  maxAgeHours = positiveNumberEnv('DB_BACKUP_MAX_AGE_HOURS', 26);
} catch (err) {
  console.error(err.message);
  process.exit(1);
}
const now = Date.now();

let entries;
try {
  entries = fs.readdirSync(outputDir, { withFileTypes: true });
} catch (err) {
  console.error(`Backup directory is not readable: ${outputDir}`);
  console.error(err.message);
  process.exit(1);
}

const backups = entries
  .filter((entry) => entry.isFile() && entry.name.endsWith('.sql.gz'))
  .map((entry) => {
    const filePath = path.join(outputDir, entry.name);
    const stat = fs.statSync(filePath);
    return { filePath, mtimeMs: stat.mtimeMs, size: stat.size };
  })
  .filter((backup) => backup.size > 0)
  .sort((a, b) => b.mtimeMs - a.mtimeMs);

if (backups.length === 0) {
  console.error(`No non-empty .sql.gz backups found in ${outputDir}`);
  process.exit(1);
}

const newest = backups[0];
const ageHours = (now - newest.mtimeMs) / (60 * 60 * 1000);

if (ageHours > maxAgeHours) {
  console.error(
    `Newest backup is ${ageHours.toFixed(1)}h old, exceeding DB_BACKUP_MAX_AGE_HOURS=${maxAgeHours}: ${newest.filePath}`
  );
  process.exit(1);
}

console.log(`Newest backup is ${ageHours.toFixed(1)}h old: ${newest.filePath}`);

function positiveNumberEnv(name, fallback) {
  const raw = process.env[name];
  if (!raw) {
    return fallback;
  }

  const value = Number(raw);
  if (!Number.isFinite(value) || value <= 0) {
    throw new Error(`${name} must be a positive number`);
  }
  return value;
}
