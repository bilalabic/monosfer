import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import { runner } from 'node-pg-migrate';
import { createApplication } from '../../dist/app.js';
import { DatabaseService } from '../../dist/infrastructure/database.module.js';
import { RedisService } from '../../dist/infrastructure/redis.module.js';
import { createLogger } from '../../dist/http/logger.js';
import { hash } from '../../dist/security/tokens.js';
import { ConfigService, parseSettings } from '../../dist/config/config.js';
import { localAuthEnv } from '../support/env.mjs';
import { challenge, login, verify, wallet } from '../support/auth.mjs';

const origin = 'http://localhost:3000';
const env = { ...process.env, ...localAuthEnv, NODE_ENV: 'test', CORS_ORIGINS: origin, CONNECTION_TIMEOUT_MS: '500',
  DATABASE_URL: process.env.DATABASE_URL ?? 'postgresql://monosfer:local-development-only@127.0.0.1:55432/monosfer_v2',
  REDIS_URL: process.env.REDIS_URL ?? 'redis://:local-development-only@127.0.0.1:56379' };

test('real auth: migrations, atomic replay, profile SQL, revocation, TTL and outage', { timeout: 60000 }, async t => {
  for (const key of ['DATABASE_URL', 'REDIS_URL']) assert.ok(['127.0.0.1', 'localhost', 'postgres', 'redis'].includes(new URL(env[key]).hostname), 'Auth integration writes require local services');
  assert.ok(['/monosfer_v2', '/monosfer_v2_test'].includes(new URL(env.DATABASE_URL).pathname), 'Use the designated local development/test database');
  const migration = { databaseUrl: env.DATABASE_URL, dir: fileURLToPath(new URL('../../migrations', import.meta.url)), direction: 'up', migrationsTable: 'pgmigrations', log: () => {} };
  await runner(migration); assert.deepEqual(await runner(migration), []);
  const logs = [];
  const { app } = await createApplication(env, createLogger({ write: line => logs.push(String(line)) }));
  const db = app.get(DatabaseService); const redis = app.get(RedisService);
  const accounts = [wallet(), wallet()];
  t.after(async () => {
    const cleanupRedis = new RedisService(new ConfigService(parseSettings(env)));
    await cleanupRedis.onModuleInit();
    try {
    // Remove only fixtures created by these random test wallets; never truncate or flush.
    for (const account of accounts) {
      const rows = await db.query('SELECT s.session_hash FROM monosfer.auth_sessions s JOIN monosfer.users u ON s.user_id = u.id WHERE u.wallet_address = $1', [account.address.toLowerCase()]);
      await cleanupRedis.del(rows.rows.map(row => `auth:session:${row.session_hash}`));
      await db.query('DELETE FROM monosfer.auth_sessions WHERE user_id IN (SELECT id FROM monosfer.users WHERE wallet_address = $1)', [account.address.toLowerCase()]);
      await db.query('DELETE FROM monosfer.users WHERE wallet_address = $1', [account.address.toLowerCase()]);
    }
    } finally { cleanupRedis.onApplicationShutdown(); await app.close(); }
  });
  const a = await login(app, accounts[0], origin);
  const b = await login(app, accounts[0], origin);
  const other = await login(app, accounts[1], origin);
  assert.equal(a.user.id, b.user.id);
  assert.equal((await db.query('SELECT session_hash FROM monosfer.auth_sessions WHERE session_hash = $1', [hash(a.rawSession)])).rowCount, 1);
  assert.equal(await redis.get(`auth:session:${hash(a.rawSession)}`), a.user.id);
  const headers = { cookie: a.cookie, origin, 'x-csrf-token': a.csrfToken };
  const updated = await app.inject({ method: 'PATCH', url: '/v1/users/me', headers, payload: { displayName: "O'Reilly", email: 'private-integration@example.com', role: 'courier', courierProfile: { vehicleType: 'car' } } });
  assert.equal(updated.statusCode, 200); assert.equal(updated.json().displayName, "O'Reilly");
  assert.deepEqual(updated.json().courierProfile, { vehicleType: 'car' });
  const partial = await app.inject({ method: 'PATCH', url: '/v1/users/me', headers, payload: { displayName: 'Only name changed' } });
  assert.equal(partial.statusCode, 200);
  assert.equal(partial.json().role, 'courier');
  assert.equal(partial.json().email, 'private-integration@example.com');
  assert.deepEqual(partial.json().courierProfile, { vehicleType: 'car' });
  const empty = await app.inject({ method: 'PATCH', url: '/v1/users/me', headers, payload: {} });
  assert.equal(empty.statusCode, 200); assert.deepEqual(empty.json(), partial.json());
  const cleared = await app.inject({ method: 'PATCH', url: '/v1/users/me', headers, payload: { email: null, courierProfile: null } });
  assert.equal(cleared.statusCode, 200); assert.equal(cleared.json().email, null); assert.equal(cleared.json().courierProfile, null);
  assert.equal(cleared.json().role, 'courier');
  assert.equal((await app.inject({ url: '/v1/users/me', headers: { cookie: other.cookie } })).json().displayName, null);

  const issued = await challenge(app, accounts[0], origin);
  const races = await Promise.all([verify(app, issued, {}, origin), verify(app, issued, {}, origin)]);
  assert.deepEqual(races.map(r => r.statusCode).sort(), [200, 401]);
  assert.equal(await redis.get(`auth:nonce:${hash(issued.nonce)}`), null);
  assert.equal((await app.inject({ method: 'DELETE', url: '/v1/auth/session', headers })).statusCode, 204);
  assert.ok((await db.query('SELECT revoked_at FROM monosfer.auth_sessions WHERE session_hash = $1', [hash(a.rawSession)])).rows[0].revoked_at);
  // Simulate stale cache after partial failure; SQL revocation must remain authoritative.
  await redis.set(`auth:session:${hash(a.rawSession)}`, a.user.id, 60);
  assert.equal((await app.inject({ url: '/v1/auth/session', headers: { cookie: a.cookie } })).statusCode, 401);
  assert.equal((await app.inject({ method: 'DELETE', url: '/v1/auth/sessions', headers: { cookie: b.cookie, origin, 'x-csrf-token': b.csrfToken } })).statusCode, 204);
  assert.equal((await app.inject({ url: '/v1/auth/session', headers: { cookie: b.cookie } })).statusCode, 401);
  assert.equal((await app.inject({ url: '/v1/auth/session', headers: { cookie: other.cookie } })).statusCode, 200);

  const { app: shortApp } = await createApplication({ ...env, NONCE_TTL_SECONDS: '1', SESSION_TTL_SECONDS: '2' }, createLogger({ write() {} }));
  try {
    const expiring = await login(shortApp, accounts[0], origin);
    const expiredNonce = await challenge(shortApp, accounts[0], origin);
    await delay(2200);
    assert.equal((await verify(shortApp, expiredNonce, {}, origin)).statusCode, 401);
    assert.equal(await redis.get(`auth:nonce:${hash(expiredNonce.nonce)}`), null);
    assert.equal(await redis.get(`auth:session:${hash(expiring.rawSession)}`), null);
    assert.equal((await shortApp.inject({ url: '/v1/auth/session', headers: { cookie: expiring.cookie } })).statusCode, 401);
  } finally { await shortApp.close(); }

  // Atomic Redis counter shares one fixed window under concurrent requests.
  const rateKey = `auth:rate:${hash(accounts[0].address)}`;
  const counts = await Promise.all(Array.from({ length: 10 }, () => redis.increment(rateKey, 1)));
  assert.deepEqual(counts.sort((a, b) => a - b), [1,2,3,4,5,6,7,8,9,10]);
  await delay(1100); assert.equal(await redis.increment(rateKey, 1), 1); await redis.del([rateKey]);
  const limited = await createApplication({ ...env, AUTH_RATE_LIMIT_MAX: '1' }, createLogger({ write() {} }));
  try { assert.equal((await limited.app.inject('/v1/auth/session')).statusCode, 429); } finally { await limited.app.close(); }

  await redis.onApplicationShutdown();
  assert.equal((await app.inject('/v1/health/ready')).statusCode, 503);
  const outage = await app.inject({ url: '/v1/auth/session', headers: { cookie: other.cookie } });
  assert.equal(outage.statusCode, 503); assert.equal(outage.json().error.code, 'SERVICE_UNAVAILABLE');
  for (const secret of [a.rawSession, a.csrfToken, a.issued.message, a.issued.nonce, 'local-development-only', 'private-integration@example.com']) assert.ok(!logs.join('').includes(secret));
});
