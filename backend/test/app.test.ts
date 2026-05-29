import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import net from 'node:net';
import { createApp } from '../src/app';

process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = process.env.JWT_SECRET ?? 'unit-test-secret-that-is-long-enough';
process.env.GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID ?? 'test-google-client-id';
process.env.APPLE_BUNDLE_ID = process.env.APPLE_BUNDLE_ID ?? 'com.jimgreco.stufftracker';

test('app echoes valid request ids on responses', async (t) => {
  const server = await listen();
  t.after(() => close(server));

  const response = await fetch(`${serverBaseUrl(server)}/health/live`, {
    headers: { 'x-request-id': 'test-request-1' },
  });

  assert.equal(response.status, 200);
  assert.equal(response.headers.get('x-request-id'), 'test-request-1');
});

test('app generates request ids when incoming ids are invalid', async (t) => {
  const server = await listen();
  t.after(() => close(server));

  const response = await fetch(`${serverBaseUrl(server)}/health/live`, {
    headers: { 'x-request-id': 'not valid' },
  });

  assert.equal(response.status, 200);
  assert.match(response.headers.get('x-request-id') ?? '', /^[a-f0-9-]{36}$/);
});

test('app serves the mobile web shell at root, /web, and item links', async (t) => {
  const server = await listen();
  t.after(() => close(server));

  for (const path of ['/', '/web/', '/items/home-1/item-1']) {
    const response = await fetch(`${serverBaseUrl(server)}${path}`);
    const body = await response.text();

    assert.equal(response.status, 200);
    assert.match(response.headers.get('content-type') ?? '', /text\/html/);
    assert.match(body, /<title>Stuff Tracker \| Home Inventory App<\/title>/);
  }
});

test('app serves Apple app site association for item universal links', async (t) => {
  const server = await listen();
  t.after(() => close(server));

  const response = await fetch(`${serverBaseUrl(server)}/.well-known/apple-app-site-association`);
  const body = await response.json() as {
    applinks: {
      details: Array<{
        appID: string;
        paths: string[];
      }>;
    };
  };

  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-type') ?? '', /application\/json/);
  assert.equal(body.applinks.details[0].appID, 'V6JPQCD336.com.jimgreco.stufftracker');
  assert.deepEqual(body.applinks.details[0].paths, ['/items/*']);
});

test('auth config exposes public web sign-in client ids only', async (t) => {
  const previousGoogleWebClientId = process.env.GOOGLE_WEB_CLIENT_ID;
  const previousAppleWebClientId = process.env.APPLE_WEB_CLIENT_ID;
  const previousAppStoreAppAppleId = process.env.APP_STORE_APP_APPLE_ID;
  const previousIosAppStoreUrl = process.env.IOS_APP_STORE_URL;
  process.env.GOOGLE_WEB_CLIENT_ID = 'web-google-client-id.apps.googleusercontent.com';
  process.env.APPLE_WEB_CLIENT_ID = 'com.example.stuff.web';
  process.env.APP_STORE_APP_APPLE_ID = '1234567890';
  delete process.env.IOS_APP_STORE_URL;

  const server = await listen();
  t.after(() => {
    restoreEnv('GOOGLE_WEB_CLIENT_ID', previousGoogleWebClientId);
    restoreEnv('APPLE_WEB_CLIENT_ID', previousAppleWebClientId);
    restoreEnv('APP_STORE_APP_APPLE_ID', previousAppStoreAppAppleId);
    restoreEnv('IOS_APP_STORE_URL', previousIosAppStoreUrl);
    return close(server);
  });

  const response = await fetch(`${serverBaseUrl(server)}/auth/config`);
  const body = await response.json() as {
    google_client_id: string | null;
    apple_client_id: string | null;
    ios_app_store_url: string | null;
  };

  assert.equal(response.status, 200);
  assert.equal(body.google_client_id, 'web-google-client-id.apps.googleusercontent.com');
  assert.equal(body.apple_client_id, 'com.example.stuff.web');
  assert.equal(body.ios_app_store_url, 'https://apps.apple.com/app/id1234567890');
  assert.equal('jwt_secret' in body, false);
});

async function listen(): Promise<http.Server> {
  const app = createApp();
  const server = app.listen(0, '127.0.0.1');
  await new Promise<void>((resolve) => server.once('listening', resolve));
  return server;
}

function close(server: http.Server): Promise<void> {
  return new Promise((resolve, reject) => {
    server.close((err) => err ? reject(err) : resolve());
  });
}

function serverBaseUrl(server: http.Server): string {
  const address = server.address() as net.AddressInfo;
  return `http://127.0.0.1:${address.port}`;
}

function restoreEnv(key: string, value: string | undefined): void {
  if (value === undefined) {
    delete process.env[key];
    return;
  }

  process.env[key] = value;
}
