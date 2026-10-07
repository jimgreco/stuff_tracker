const fs = require('node:fs');

function origin(value) {
  let url;
  try { url = new URL(value); } catch { throw new Error('PRODUCTION_BASE_URL is missing or invalid'); }
  if (url.protocol !== 'https:' || url.username || url.password || url.pathname !== '/' || url.search || url.hash)
    throw new Error('PRODUCTION_BASE_URL must be an HTTPS origin');
  return url.origin;
}

async function checkHealth(value, fetcher = fetch) {
  const base = origin(value);
  const results = [];
  for (const path of ['/health/live', '/health']) {
    let ok = false;
    try {
      const response = await fetcher(base + path, { redirect: 'error', signal: AbortSignal.timeout(15000) });
      const body = response.ok ? await response.json() : null;
      ok = body?.ok === true && (path !== '/health' || body.db === true);
    } catch { /* Never log upstream bodies, request URLs, or fetch exceptions. */ }
    results.push({ path, ok });
  }
  return results;
}

async function main() {
  const results = await checkHealth(process.env.PRODUCTION_BASE_URL);
  for (const { path, ok } of results) console.log(`${ok ? 'PASS' : 'FAIL'} ${path}`);
  if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY,
    results.map(({ path, ok }) => `- ${path}: ${ok ? 'passed' : 'failed'}`).join('\n') + '\n');
  if (results.some(result => !result.ok)) process.exitCode = 1;
}
if (require.main === module) main().catch(() => {
  console.error('::error::Production health configuration or probe failed; verify PRODUCTION_BASE_URL.');
  process.exitCode = 1;
});
module.exports = { origin, checkHealth };
