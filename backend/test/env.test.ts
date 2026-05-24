import test from 'node:test';
import assert from 'node:assert/strict';
import { validateRuntimeEnvironment } from '../src/lib/env';

test('runtime validation does not require Apple Sign-In configuration', () => {
  const previous = snapshotEnv([
    'NODE_ENV',
    'DATABASE_URL',
    'JWT_SECRET',
    'GOOGLE_CLIENT_ID',
    'APPLE_BUNDLE_ID',
    'APPLE_WEB_CLIENT_ID',
  ]);

  process.env.NODE_ENV = 'production';
  process.env.DATABASE_URL = 'postgresql://localhost/stuff_test';
  process.env.JWT_SECRET = 'production-secret-with-enough-characters';
  process.env.GOOGLE_CLIENT_ID = 'ios-google-client-id';
  delete process.env.APPLE_BUNDLE_ID;
  delete process.env.APPLE_WEB_CLIENT_ID;

  try {
    assert.doesNotThrow(() => validateRuntimeEnvironment());
  } finally {
    restoreEnv(previous);
  }
});

function snapshotEnv(names: string[]): Map<string, string | undefined> {
  return new Map(names.map((name) => [name, process.env[name]]));
}

function restoreEnv(values: Map<string, string | undefined>): void {
  for (const [name, value] of values) {
    if (value === undefined) {
      delete process.env[name];
    } else {
      process.env[name] = value;
    }
  }
}
