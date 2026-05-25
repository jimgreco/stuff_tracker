import test from 'node:test';
import assert from 'node:assert/strict';

import { createErrorRateTracker } from '../src/lib/errorRateAlerts';

test('error-rate tracker alerts after the configured 5xx threshold is crossed', () => {
  let now = 1000;
  const alerts: Array<{ event: string; message: string; error?: unknown }> = [];
  const tracker = createErrorRateTracker({
    cooldownMs: 60000,
    enabled: true,
    max5xxPercent: 50,
    min5xx: 2,
    minRequests: 4,
    now: () => now,
    sendAlert: (alert) => { alerts.push(alert); },
    windowMs: 60000,
  });

  tracker.record({ method: 'GET', path: '/health', status: 200 });
  now += 1000;
  tracker.record({ method: 'GET', path: '/homes', status: 200 });
  now += 1000;
  tracker.record({ method: 'GET', path: '/homes', requestId: 'req-1', status: 500 });
  now += 1000;
  tracker.record({ method: 'POST', path: '/homes', requestId: 'req-2', status: 503 });

  assert.equal(alerts.length, 1);
  assert.equal(alerts[0].event, 'http_error_rate');
  assert.match(alerts[0].message, /5xx error rate 50%/);
  assert.deepEqual(alerts[0].error, {
    method: 'POST',
    path: '/homes',
    status: 503,
    window_ms: 60000,
    request_count: 4,
    error_count: 2,
    error_percent: 50,
  });
});

test('error-rate tracker suppresses duplicate alerts during cooldown', () => {
  let now = 1000;
  let alertCount = 0;
  const tracker = createErrorRateTracker({
    cooldownMs: 60000,
    enabled: true,
    max5xxPercent: 1,
    min5xx: 1,
    minRequests: 1,
    now: () => now,
    sendAlert: () => { alertCount += 1; },
    windowMs: 60000,
  });

  tracker.record({ method: 'GET', path: '/first', status: 500 });
  now += 1000;
  tracker.record({ method: 'GET', path: '/second', status: 500 });
  now += 60000;
  tracker.record({ method: 'GET', path: '/third', status: 500 });

  assert.equal(alertCount, 2);
});
