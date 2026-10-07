async function notify(env, fetcher = fetch) {
  let url;
  try { url = new URL(env.WEBHOOK_URL || ''); } catch { throw new Error('Operations alert destination is not configured'); }
  if (url.protocol !== 'https:' || url.username || url.password || url.hash)
    throw new Error('Operations alert destination must use HTTPS');
  const payload = {
    timestamp: new Date().toISOString(), service: env.GITHUB_REPOSITORY,
    event: 'github_workflow_alert', level: env.ALERT_LEVEL || 'error',
    title: env.ALERT_TITLE, summary: env.ALERT_SUMMARY,
    repository: env.GITHUB_REPOSITORY, workflow: env.GITHUB_WORKFLOW,
    ref: env.GITHUB_REF_NAME, sha: env.GITHUB_SHA, run_id: env.GITHUB_RUN_ID,
    run_url: `https://github.com/${env.GITHUB_REPOSITORY}/actions/runs/${env.GITHUB_RUN_ID}`,
  };
  try {
    const response = await fetcher(url.href, { method: 'POST', redirect: 'error',
      signal: AbortSignal.timeout(10000), headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload) });
    if (!response.ok) throw new Error();
  } catch { throw new Error('Operations alert delivery failed'); }
}
if (require.main === module) notify(process.env).catch(error => {
  console.error('::error::' + error.message);
  process.exitCode = 1;
});
module.exports = { notify };
