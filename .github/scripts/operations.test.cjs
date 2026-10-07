const { test } = require('node:test');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const { join } = require('node:path');
const { notificationPolicy, notify } = require('./notify-operations.cjs');

test('an explicit recognized notification mode is required', async () => {
  for (const mode of [undefined, '', 'email', 'automatic'])
    await assert.rejects(notify({ OPERATIONS_ALERT_MODE: mode }), /explicit operations alert mode/);
});
test('github-email never sends even if a webhook happens to be present', async () => {
  let calls = 0;
  for (const webhook of [undefined, 'https://example.com/private-token', 'not-a-url']) {
    const result = await notify({ OPERATIONS_ALERT_MODE: 'github-email', WEBHOOK_URL: webhook }, async () => { calls++; });
    assert.deepEqual(result, { mode: 'github-email', webhookAttempted: false });
  }
  assert.equal(calls, 0);
});
test('explicit webhook mode fails without a valid HTTPS destination and cannot fall back to email', async () => {
  let calls = 0;
  for (const url of ['', 'http://example.com', 'https://user:secret@example.com', '#token'])
    await assert.rejects(notify({ OPERATIONS_ALERT_MODE: 'webhook', WEBHOOK_URL: url }, async () => { calls++; }));
  assert.equal(calls, 0);
});
test('synthetic webhook delivery is bounded, rejects redirects, and contains no secrets', async () => {
  const env = { OPERATIONS_ALERT_MODE: 'webhook', WEBHOOK_URL: 'https://example.com/private-token', GITHUB_REPOSITORY: 'example/repo', GITHUB_RUN_ID: '123', ALERT_TITLE: 'Synthetic', ALERT_SUMMARY: 'freshness=failure' };
  let calls = 0;
  const result = await notify(env, async (url, options) => {
    calls++; assert.equal(options.redirect, 'error'); assert.ok(options.signal);
    assert.equal(options.method, 'POST'); assert.ok(!options.body.includes('private-token'));
    assert.equal(JSON.parse(options.body).run_url, 'https://github.com/example/repo/actions/runs/123');
    return { ok: true };
  });
  assert.equal(calls, 1); assert.equal(result.webhookAttempted, true);
});
test('provider failures expose only a fixed error and never retry a send', async () => {
  let calls = 0;
  await assert.rejects(notify({ OPERATIONS_ALERT_MODE: 'webhook', WEBHOOK_URL: 'https://example.com/private-token' }, async () => { calls++; throw new Error('private-token'); }), error => error.message === 'Operations alert delivery failed');
  assert.equal(calls, 1);
});
test('CLI email mode succeeds without credentials and states its coverage limits', () => {
  const result = spawnSync(process.execPath, [join(__dirname, 'notify-operations.cjs')], {
    encoding: 'utf8', env: { OPERATIONS_ALERT_MODE: 'github-email' },
  });
  assert.equal(result.status, 0); assert.match(result.stdout, /does not send or verify receipt/);
  assert.match(result.stdout, /No missing-run or backend-runtime coverage/);
});
test('check-only validates configuration without contacting a webhook', () => {
  const result = spawnSync(process.execPath, [join(__dirname, 'notify-operations.cjs'), '--check'], {
    encoding: 'utf8', env: { OPERATIONS_ALERT_MODE: 'webhook', WEBHOOK_URL: 'https://127.0.0.1:1/synthetic-never-send' },
    timeout: 1000,
  });
  assert.equal(result.status, 0); assert.match(result.stdout, /delivery has not been tested/);
  assert.ok(!result.stdout.includes('synthetic-never-send'));
});
