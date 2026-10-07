import test from 'node:test';
import assert from 'node:assert/strict';
import { Controller, Post, Body, Get, Module } from '@nestjs/common';
import { IsString } from 'class-validator';
import { testApplication } from '../support/app.mjs';

// Test-only route exercises the actual global DTO pipe without adding domain endpoints.
class Input { name; }
IsString()(Input.prototype, 'name');
class ProbeController {
  submit(input) { return input; }
  fail() { throw new Error('private-password recipient-phone access-token'); }
}
Controller('probe')(ProbeController);
Post()(ProbeController.prototype, 'submit', Object.getOwnPropertyDescriptor(ProbeController.prototype, 'submit'));
Body()(ProbeController.prototype, 'submit', 0);
Reflect.defineMetadata('design:paramtypes', [Input], ProbeController.prototype, 'submit');
Get('fail')(ProbeController.prototype, 'fail', Object.getOwnPropertyDescriptor(ProbeController.prototype, 'fail'));
class ProbeModule {}
Module({ controllers: [ProbeController] })(ProbeModule);

test('health, request IDs, headers, public contract, and legacy isolation', async t => {
  const { app, document } = await testApplication();
  t.after(() => app.close());
  const result = await app.inject({ url: '/v1/health/live', headers: { 'x-request-id': 'untrusted-id' } });
  assert.equal(result.statusCode, 200);
  assert.deepEqual(result.json(), { status: 'ok' });
  assert.match(result.headers['x-request-id'], /^[\da-f-]{36}$/);
  assert.equal(result.headers['cache-control'], 'no-store');
  assert.equal(result.headers['x-content-type-options'], 'nosniff');
  assert.equal((await app.inject('/v1/health/ready')).statusCode, 200);
  assert.equal((await app.inject('/api/health')).statusCode, 404);
  const missing = await app.inject('/missing');
  assert.deepEqual(missing.json(), { error: { code: 'NOT_FOUND', message: 'Resource not found', requestId: missing.headers['x-request-id'] } });
  assert.deepEqual(Object.keys(document.paths).sort(), [
    '/v1/auth/session', '/v1/auth/sessions', '/v1/auth/siwe/nonce', '/v1/auth/siwe/verify', '/v1/deliveries', '/v1/deliveries/{id}',
    '/v1/deliveries/{id}/bids', '/v1/deliveries/{id}/evidence', '/v1/deliveries/{id}/evidence/{evidenceId}', '/v1/deliveries/{id}/evidence/{evidenceId}/content',
    '/v1/deliveries/{id}/pickup-acceptances','/v1/deliveries/{id}/return-acceptances','/v1/deliveries/{id}/pod-attestations',
    '/v1/deliveries/{id}/route', '/v1/deliveries/{id}/tracking/location', '/v1/deliveries/{id}/tracking/sessions', '/v1/development/dataset', '/v1/health/live', '/v1/health/ready',
    '/v1/indexer/status', '/v1/notifications', '/v1/quotes/delivery', '/v1/quotes/{quoteDigest}', '/v1/quotes/{quoteDigest}/refresh', '/v1/users/me',
    '/v1/admin/audit','/v1/ops/metrics','/v1/ops/status','/v1/ops/traces/{requestId}', '/v1/support/cases','/v1/support/cases/{caseId}',
    '/v1/support/deliveries/{id}','/v1/support/deliveries/{id}/evidence','/v1/support/deliveries/{id}/evidence/{evidenceId}/content',
    '/v1/support/deliveries/{id}/private','/v1/support/wallets/{wallet}/reputation','/v1/users/me/reputation',
  ].sort());
  assert.equal((await app.inject('/v1/openapi.json')).statusCode, 200);
  assert.equal((await app.inject('/v1/docs')).statusCode, 404);
});

test('readiness fails safely when either dependency fails', async t => {
  for (const dependency of ['database', 'redis']) {
    const { app } = await testApplication({ [dependency]: { ping: async () => { throw new Error('private-password'); } } });
    t.after(() => app.close());
    const response = await app.inject('/v1/health/ready');
    assert.equal(response.statusCode, 503);
    assert.equal(response.json().error.code, 'SERVICE_UNAVAILABLE');
    assert.equal(response.body.includes('private-password'), false);
    assert.equal((await app.inject('/v1/health/live')).statusCode, 200);
  }
});

test('DTO validation, parser errors, size limits and error redaction', async t => {
  const { app, logs } = await testApplication({ imports: [ProbeModule], env: { NODE_ENV: 'production', BODY_LIMIT_BYTES: '1024' } });
  t.after(() => app.close());
  assert.equal((await app.inject({ method: 'POST', url: '/v1/probe', payload: { name: 'valid' } })).statusCode, 201);
  for (const payload of [{ name: 'valid', token: 'access-token' }, { name: 3 }, {}]) {
    const response = await app.inject({ method: 'POST', url: '/v1/probe', payload });
    assert.equal(response.statusCode, 400);
    assert.equal(response.json().error.code, 'BAD_REQUEST');
  }
  const invalidJson = await app.inject({ method: 'POST', url: '/v1/probe', headers: { 'content-type': 'application/json' }, payload: '{private-password' });
  assert.equal(invalidJson.statusCode, 400);
  assert.equal(invalidJson.json().error.code, 'BAD_REQUEST');
  const oversized = await app.inject({ method: 'POST', url: '/v1/probe', payload: { name: 'x'.repeat(2000) } });
  assert.equal(oversized.statusCode, 413);
  assert.equal(oversized.json().error.code, 'PAYLOAD_TOO_LARGE');
  const failure = await app.inject({ url: '/v1/probe/fail?token=access-token', headers: { authorization: 'Bearer access-token', cookie: 'secret=private-password' } });
  assert.equal(failure.statusCode, 500);
  assert.equal(failure.json().error.message, 'Internal server error');
  for (const secret of ['private-password', 'access-token', 'recipient-phone']) {
    assert.equal(failure.body.includes(secret), false);
    assert.equal(logs.join('').includes(secret), false);
  }
  assert.ok(logs.some(line => JSON.parse(line).event === 'request_failed'));
});

test('CORS is allowlisted and preflight uses security policy', async t => {
  const { app } = await testApplication();
  t.after(() => app.close());
  const allowed = await app.inject({ url: '/v1/health/live', headers: { origin: 'https://app.example.com' } });
  assert.equal(allowed.headers['access-control-allow-origin'], 'https://app.example.com');
  const rejected = await app.inject({ url: '/v1/health/live', headers: { origin: 'https://evil.example.com' } });
  assert.equal(rejected.headers['access-control-allow-origin'], undefined);
  const preflight = await app.inject({ method: 'OPTIONS', url: '/v1/health/live', headers: { origin: 'https://app.example.com', 'access-control-request-method': 'GET' } });
  assert.equal(preflight.statusCode, 204);
});

test('Swagger UI is available only in development', async t => {
  const { app } = await testApplication({ env: { NODE_ENV: 'development' } });
  t.after(() => app.close());
  assert.equal((await app.inject('/v1/docs')).statusCode, 200);
});

test('application close disposes both dependency providers exactly once', async () => {
  const calls = { database: 0, redis: 0 };
  const providers = Object.fromEntries(Object.keys(calls).map(name => [name, {
    ping: async () => true,
    onApplicationShutdown: () => { calls[name] += 1; },
  }]));
  const { app } = await testApplication(providers);
  await app.close();
  assert.deepEqual(calls, { database: 1, redis: 1 });
});

test('structured logger redacts sensitive object fields', async t => {
  const { app, logger, logs } = await testApplication();
  t.after(() => app.close());
  logger.info({ token: 'TOP_SECRET', body: { address: 'TOP_SECRET' }, req: { headers: { authorization: 'TOP_SECRET' } } });
  assert.equal(logs.join('').includes('TOP_SECRET'), false);
  assert.ok(logs.join('').includes('[REDACTED]'));
});
