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

test('app serves the mobile web shell at root and /web', async (t) => {
  const server = await listen();
  t.after(() => close(server));

  for (const path of ['/', '/web/']) {
    const response = await fetch(`${serverBaseUrl(server)}${path}`);
    const body = await response.text();

    assert.equal(response.status, 200);
    assert.match(response.headers.get('content-type') ?? '', /text\/html/);
    assert.match(body, /<title>Stuff Tracker<\/title>/);
  }
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
