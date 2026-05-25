import { NextFunction, Request, Response } from 'express';

import { OperationalAlert, sendOperationalAlert } from './alerts';
import { getIntegerEnv, isProduction } from './env';

type OperationalAlertSender = (alert: OperationalAlert) => Promise<void> | void;

interface ErrorRateRecord {
  timestamp: number;
  status: number;
}

interface ErrorRateAlertInput {
  method: string;
  path: string;
  requestId?: string;
  status: number;
}

interface ErrorRateTrackerOptions {
  cooldownMs?: number;
  enabled?: boolean;
  max5xxPercent?: number;
  min5xx?: number;
  minRequests?: number;
  now?: () => number;
  sendAlert?: OperationalAlertSender;
  windowMs?: number;
}

export function createErrorRateAlertMiddleware(options: ErrorRateTrackerOptions = {}) {
  const tracker = createErrorRateTracker(options);

  return (req: Request, res: Response, next: NextFunction): void => {
    res.on('finish', () => {
      tracker.record({
        method: req.method,
        path: req.path,
        requestId: res.locals.requestId,
        status: res.statusCode,
      });
    });

    next();
  };
}

export function createErrorRateTracker(options: ErrorRateTrackerOptions = {}) {
  const enabled = options.enabled ?? isProduction();
  const now = options.now ?? (() => Date.now());
  const sendAlert = options.sendAlert ?? sendOperationalAlert;
  const windowMs = options.windowMs ?? (enabled ? getIntegerEnv('ERROR_RATE_ALERT_WINDOW_MS', 300000) : 300000);
  const minRequests = options.minRequests ?? (enabled ? getIntegerEnv('ERROR_RATE_ALERT_MIN_REQUESTS', 20) : 20);
  const min5xx = options.min5xx ?? (enabled ? getIntegerEnv('ERROR_RATE_ALERT_MIN_5XX', 5) : 5);
  const max5xxPercent = options.max5xxPercent ?? (enabled ? getIntegerEnv('ERROR_RATE_ALERT_5XX_PERCENT', 20) : 20);
  const cooldownMs = options.cooldownMs ?? (enabled ? getIntegerEnv('ERROR_RATE_ALERT_COOLDOWN_MS', 900000) : 900000);
  const records: ErrorRateRecord[] = [];
  let lastAlertAt = Number.NEGATIVE_INFINITY;

  function record(input: ErrorRateAlertInput): void {
    if (!enabled) {
      return;
    }

    const timestamp = now();
    records.push({ timestamp, status: input.status });
    prune(timestamp);

    if (input.status < 500 || timestamp - lastAlertAt < cooldownMs) {
      return;
    }

    const requestCount = records.length;
    const errorCount = records.filter((entry) => entry.status >= 500).length;
    const errorPercent = requestCount === 0 ? 0 : (errorCount / requestCount) * 100;

    if (requestCount < minRequests || errorCount < min5xx || errorPercent < max5xxPercent) {
      return;
    }

    lastAlertAt = timestamp;
    const roundedPercent = Number(errorPercent.toFixed(1));

    void Promise.resolve(sendAlert({
      level: 'error',
      event: 'http_error_rate',
      request_id: input.requestId,
      message: `5xx error rate ${roundedPercent}% over ${Math.round(windowMs / 1000)}s (${errorCount}/${requestCount})`,
      error: {
        method: input.method,
        path: input.path,
        status: input.status,
        window_ms: windowMs,
        request_count: requestCount,
        error_count: errorCount,
        error_percent: roundedPercent,
      },
    })).catch((err: unknown) => {
      const message = err instanceof Error ? err.message : String(err);
      console.error(`Error-rate alert failed: ${message}`);
    });
  }

  function prune(timestamp: number): void {
    const cutoff = timestamp - windowMs;
    while (records.length > 0 && records[0].timestamp < cutoff) {
      records.shift();
    }
  }

  return { record };
}
