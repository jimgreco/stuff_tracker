import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

process.env.JWT_SECRET = process.env.JWT_SECRET ?? 'unit-test-secret';

const requireModule = createRequire(import.meta.url);
const { signToken, verifyToken } = requireModule('../src/lib/jwt') as typeof import('../src/lib/jwt');
const { requireAuth } = requireModule('../src/middleware/auth') as typeof import('../src/middleware/auth');

test('JWT helper signs and verifies auth payloads', () => {
  const token = signToken({ userId: 'user-1', email: 'user@example.com' });
  const payload = verifyToken(token);

  assert.equal(payload.userId, 'user-1');
  assert.equal(payload.email, 'user@example.com');
});

test('requireAuth rejects missing bearer token', () => {
  const res = createMockResponse();
  let nextCalled = false;

  requireAuth({ headers: {} } as any, res as any, () => { nextCalled = true; });

  assert.equal(nextCalled, false);
  assert.equal(res.statusCode, 401);
  assert.deepEqual(res.body, { error: 'Missing or invalid Authorization header' });
});

test('requireAuth rejects invalid bearer token', () => {
  const res = createMockResponse();
  let nextCalled = false;

  requireAuth(
    { headers: { authorization: 'Bearer not-a-real-token' } } as any,
    res as any,
    () => { nextCalled = true; }
  );

  assert.equal(nextCalled, false);
  assert.equal(res.statusCode, 401);
  assert.deepEqual(res.body, { error: 'Invalid or expired token' });
});

test('requireAuth attaches verified user and calls next', () => {
  const req: any = {
    headers: {
      authorization: `Bearer ${signToken({ userId: 'user-1', email: 'user@example.com' })}`,
    },
  };
  const res = createMockResponse();
  let nextCalled = false;

  requireAuth(req, res as any, () => { nextCalled = true; });

  assert.equal(nextCalled, true);
  assert.equal(req.user.userId, 'user-1');
  assert.equal(req.user.email, 'user@example.com');
  assert.equal(res.statusCode, undefined);
});

function createMockResponse() {
  return {
    statusCode: undefined as number | undefined,
    body: undefined as unknown,
    status(code: number) {
      this.statusCode = code;
      return this;
    },
    json(body: unknown) {
      this.body = body;
      return this;
    },
  };
}
