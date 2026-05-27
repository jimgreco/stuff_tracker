const TRUE_VALUES = new Set(['1', 'true', 'yes', 'on']);

export function isProduction(): boolean {
  return process.env.NODE_ENV === 'production';
}

export function getRequiredEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`${name} is required`);
  }
  return value;
}

export function getIntegerEnv(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) {
    return fallback;
  }

  const value = Number(raw);
  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }

  return value;
}

export function getOptionalIntegerEnv(name: string): number | undefined {
  const raw = process.env[name]?.trim();
  if (!raw) {
    return undefined;
  }

  const value = Number(raw);
  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }

  return value;
}

export function getOptionalStringEnv(name: string): string | undefined {
  const value = process.env[name]?.trim();
  return value || undefined;
}

export function getBooleanEnv(name: string, fallback = false): boolean {
  const raw = process.env[name];
  if (!raw) {
    return fallback;
  }

  return TRUE_VALUES.has(raw.trim().toLowerCase());
}

export function getCsvEnv(name: string): string[] {
  return (process.env[name] ?? '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
}

export function assertStrongJwtSecret(secret: string): void {
  if (isProduction() && secret.length < 32) {
    throw new Error('JWT_SECRET must be at least 32 characters in production');
  }
}

export function validateRuntimeEnvironment(): void {
  const required = ['DATABASE_URL', 'JWT_SECRET', 'GOOGLE_CLIENT_ID'];
  for (const name of required) {
    getRequiredEnv(name);
  }

  assertStrongJwtSecret(getRequiredEnv('JWT_SECRET'));
}
