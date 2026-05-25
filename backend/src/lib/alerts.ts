import { getIntegerEnv } from './env';

interface OperationalAlert {
  level: 'error' | 'warning' | 'info';
  event: string;
  message: string;
  request_id?: string;
  error?: unknown;
}

export function operationalAlertWebhookUrl(): string | undefined {
  return process.env.OPERATIONS_ALERT_WEBHOOK_URL?.trim()
    || process.env.ERROR_ALERT_WEBHOOK_URL?.trim()
    || undefined;
}

export async function sendOperationalAlert(alert: OperationalAlert): Promise<void> {
  const url = operationalAlertWebhookUrl();
  if (!url) {
    return;
  }

  const timeoutMs = getIntegerEnv('OPERATIONS_ALERT_TIMEOUT_MS', 3000);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        timestamp: new Date().toISOString(),
        service: 'stuff-tracker',
        ...alert,
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      console.error(`Operational alert webhook failed with HTTP ${response.status}`);
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`Operational alert webhook failed: ${message}`);
  } finally {
    clearTimeout(timeout);
  }
}
