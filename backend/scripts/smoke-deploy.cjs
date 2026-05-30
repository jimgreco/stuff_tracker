#!/usr/bin/env node
const jwt = require('jsonwebtoken');
const { Pool } = require('pg');

const baseUrl = (process.env.SMOKE_BASE_URL || `http://127.0.0.1:${process.env.PORT || 3002}`).replace(/\/+$/, '');

async function main() {
  const pool = new Pool({ connectionString: requiredEnv('DATABASE_URL') });
  const email = `deploy-smoke-${Date.now()}-${process.pid}@stufftracker.local`;
  let token;
  let userId;
  let homeId;
  let itemId;

  try {
    await expectJson('/health/live', 200, (body) => body.ok === true);
    await expectJson('/health', 200, (body) => body.ok === true && body.db === true);
    validateAuthConfig(await requestJson('/auth/config'));

    const user = await createSmokeUser(pool, email);
    userId = user.id;
    token = jwt.sign({ userId: user.id, email: user.email }, requiredEnv('JWT_SECRET'), { expiresIn: '10m' });

    const homes = await requestJson('/homes', { token });
    if (!Array.isArray(homes)) {
      throw new Error('/homes did not return an array for an authenticated smoke user');
    }

    const home = await requestJson('/homes', {
      method: 'POST',
      token,
      body: { name: `Deploy Smoke ${new Date().toISOString()}`, icon: 'checkmark.shield' },
      expectedStatus: 201,
    });
    assertString(home.id, 'created home id');
    homeId = home.id;

    const item = await requestJson(`/homes/${homeId}/items`, {
      method: 'POST',
      token,
      body: { name: 'Deploy Smoke Item', quantity: 1, properties: [], photo_urls: [], documents: [] },
      expectedStatus: 201,
    });
    assertString(item.id, 'created item id');
    itemId = item.id;

    const detail = await requestJson(`/homes/${homeId}`, { token });
    if (!Array.isArray(detail.items) || !detail.items.some((row) => row.id === itemId)) {
      throw new Error('created smoke item was not returned from home detail');
    }

    const upload = await requestJson(`/homes/${homeId}/items/uploads`, {
      method: 'POST',
      token,
      body: {
        kind: 'photo',
        file_name: 'deploy-smoke.jpg',
        content_type: 'image/jpeg',
        size_bytes: 4,
      },
      expectedStatus: 201,
    });
    assertString(upload.uploadUrl, 'upload URL');
    assertString(upload.fileUrl, 'file URL');
    assertString(upload.key, 'upload key');
    if (upload.headers?.['Content-Type'] !== 'image/jpeg') {
      throw new Error('upload signing did not return the expected Content-Type header');
    }

    await requestNoBody(`/homes/${homeId}/items/${itemId}`, { method: 'DELETE', token, expectedStatus: 204 });
    itemId = undefined;
    await requestNoBody(`/homes/${homeId}`, { method: 'DELETE', token, expectedStatus: 204 });
    homeId = undefined;

    console.log('deploy smoke tests passed');
  } finally {
    await cleanup({ pool, email, token, homeId, itemId, userId });
    await pool.end();
  }
}

async function createSmokeUser(pool, email) {
  const { rows } = await pool.query(
    `INSERT INTO users (email, name)
     VALUES ($1, $2)
     RETURNING id, email`,
    [email, 'Deploy Smoke']
  );
  return rows[0];
}

async function cleanup({ pool, email, token, homeId, itemId, userId }) {
  if (token && homeId && itemId) {
    await requestNoBody(`/homes/${homeId}/items/${itemId}`, { method: 'DELETE', token, expectedStatus: 204 })
      .catch((err) => console.warn(`smoke cleanup item delete failed: ${err.message}`));
  }

  if (token && homeId) {
    await requestNoBody(`/homes/${homeId}`, { method: 'DELETE', token, expectedStatus: 204 })
      .catch((err) => console.warn(`smoke cleanup home delete failed: ${err.message}`));
  }

  if (userId) {
    await pool.query('DELETE FROM users WHERE id = $1 AND email = $2', [userId, email]);
  }
}

async function expectJson(path, expectedStatus, predicate) {
  const body = await requestJson(path, { expectedStatus });
  if (!predicate(body)) {
    throw new Error(`${path} returned an unexpected payload: ${JSON.stringify(body)}`);
  }
}

async function requestJson(path, options = {}) {
  const response = await request(path, options);
  const text = await response.text();
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`${path} did not return JSON: ${text.slice(0, 200)}`);
  }
}

async function requestNoBody(path, options = {}) {
  await request(path, options);
}

async function request(path, options = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    method: options.method || 'GET',
    headers: {
      ...(options.body ? { 'Content-Type': 'application/json' } : {}),
      ...(options.token ? { Authorization: `Bearer ${options.token}` } : {}),
    },
    body: options.body ? JSON.stringify(options.body) : undefined,
  });

  const expectedStatus = options.expectedStatus || 200;
  if (response.status !== expectedStatus) {
    const text = await response.text();
    throw new Error(`${path} returned HTTP ${response.status}, expected ${expectedStatus}: ${text.slice(0, 200)}`);
  }
  return response;
}

function assertString(value, label) {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`missing ${label}`);
  }
}

function validateAuthConfig(body) {
  if (!body || typeof body !== 'object') {
    throw new Error(`/auth/config returned an unexpected payload: ${JSON.stringify(body)}`);
  }

  for (const key of ['google_client_id', 'apple_client_id', 'ios_app_store_url']) {
    if (body[key] !== null && typeof body[key] !== 'string') {
      throw new Error(`/auth/config returned an invalid ${key}: ${JSON.stringify(body[key])}`);
    }
  }

  if (!body.google_client_id && !body.apple_client_id) {
    console.warn('No web sign-in providers are configured; set STUFF_GOOGLE_WEB_CLIENT_ID or STUFF_APPLE_WEB_CLIENT_ID to enable production web login.');
  }
}

function requiredEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`${name} is required for deploy smoke tests`);
  }
  return value;
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
