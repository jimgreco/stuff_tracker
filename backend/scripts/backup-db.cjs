const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

require('dotenv').config();

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  console.error('DATABASE_URL is required');
  process.exit(1);
}

const outputDir = process.env.DB_BACKUP_DIR || path.join(__dirname, '..', 'backups');
fs.mkdirSync(outputDir, { recursive: true });

const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const outputPath = path.join(outputDir, `stuff-tracker-${stamp}.sql.gz`);

const dump = spawn('pg_dump', [databaseUrl], { stdio: ['ignore', 'pipe', 'inherit'] });
const gzip = spawn('gzip', ['-c'], { stdio: ['pipe', 'pipe', 'inherit'] });
const output = fs.createWriteStream(outputPath, { mode: 0o600 });

dump.stdout.pipe(gzip.stdin);
gzip.stdout.pipe(output);

dump.on('error', (err) => {
  console.error('Failed to start pg_dump:', err.message);
  process.exit(1);
});

gzip.on('error', (err) => {
  console.error('Failed to start gzip:', err.message);
  process.exit(1);
});

dump.on('close', (code) => {
  if (code !== 0) {
    console.error(`pg_dump exited with code ${code}`);
    process.exit(code ?? 1);
  }
});

gzip.on('close', (code) => {
  if (code !== 0) {
    console.error(`gzip exited with code ${code}`);
    process.exit(code ?? 1);
  }
});

output.on('close', () => {
  console.log(`Database backup written to ${outputPath}`);
});
