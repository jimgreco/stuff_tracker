const fs = require('node:fs');

function notificationPolicy(env) {
  const mode = env.OPERATIONS_ALERT_MODE;
  if (mode === 'github-email') return { mode };
  if (mode !== 'webhook') throw new Error('Select an explicit operations alert mode: github-email or webhook');
  let url;
  try { url = new URL(env.WEBHOOK_URL || ''); } catch { throw new Error('Operations webhook destination is not configured'); }
  if (url.protocol !== 'https:' || url.username || url.password || url.hash)
    throw new Error('Operations webhook destination must use HTTPS');
  return { mode, url: url.href };
}

async function notify(env, fetcher = fetch) {
  const policy = notificationPolicy(env);
  // GitHub owns failure-email delivery. This mode never calls a mail provider,
  // accesses mail credentials, or infers that a particular email was received.
  if (policy.mode === 'github-email') return { mode: policy.mode, webhookAttempted: false };
  const payload = {
    timestamp: new Date().toISOString(), service: env.GITHUB_REPOSITORY,
    event: 'github_workflow_alert', level: env.ALERT_LEVEL || 'error',
    title: env.ALERT_TITLE, summary: env.ALERT_SUMMARY,
    repository: env.GITHUB_REPOSITORY, workflow: env.GITHUB_WORKFLOW,
    ref: env.GITHUB_REF_NAME, sha: env.GITHUB_SHA, run_id: env.GITHUB_RUN_ID,
    run_url: `https://github.com/${env.GITHUB_REPOSITORY}/actions/runs/${env.GITHUB_RUN_ID}`,
  };
  try {
    const response = await fetcher(policy.url, { method: 'POST', redirect: 'error',
      signal: AbortSignal.timeout(10000), headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload) });
    if (!response.ok) throw new Error();
  } catch { throw new Error('Operations alert delivery failed'); }
  return { mode: policy.mode, webhookAttempted: true };
}

async function main(env = process.env, checkOnly = process.argv.includes('--check')) {
  const policy = notificationPolicy(env);
  if (!checkOnly) await notify(env);
  const message = policy.mode === 'github-email'
    ? 'GitHub-email mode selected. GitHub manages workflow-failure email; this job does not send or verify receipt. No missing-run or backend-runtime coverage.'
    : checkOnly ? 'Webhook configuration format passed; delivery has not been tested.'
      : 'Operations webhook accepted the request; recipient receipt remains separate.';
  console.log(message);
  if (env.GITHUB_STEP_SUMMARY) fs.appendFileSync(env.GITHUB_STEP_SUMMARY, message + '\n');
}
if (require.main === module) main().catch(error => {
  console.error('::error::' + error.message);
  process.exitCode = 1;
});
module.exports = { notificationPolicy, notify };
