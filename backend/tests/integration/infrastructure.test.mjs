import test from 'node:test';
import assert from 'node:assert/strict';
import { runner } from 'node-pg-migrate';
import { fileURLToPath } from 'node:url';
import { createApplication } from '../../dist/app.js';
import { createLogger } from '../../dist/http/logger.js';
import { DatabaseService } from '../../dist/infrastructure/database.module.js';
import { RedisService } from '../../dist/infrastructure/redis.module.js';
import { localAuthEnv } from '../support/env.mjs';

const env = {
  ...process.env, ...localAuthEnv, NODE_ENV: 'test',
  DATABASE_URL: process.env.DATABASE_URL ?? 'postgresql://monosfer:local-development-only@127.0.0.1:55432/monosfer_v2',
  REDIS_URL: process.env.REDIS_URL ?? 'redis://:local-development-only@127.0.0.1:56379',
  CORS_ORIGINS: 'http://localhost:3000', CONNECTION_TIMEOUT_MS: '300',
};
// Integration commands intentionally fail (not skip) when local infrastructure is unavailable.
test('realtime starts without framework errors and serves health without API telemetry', { timeout: 15000 }, async t => {
  const logs = [];
  const { app } = await createApplication(env, createLogger({ write: line => logs.push(JSON.parse(String(line))) }), true);
  t.after(() => app.close());
  assert.equal((await app.inject('/v1/health/ready')).statusCode, 200);
  assert.equal((await app.inject('/v1/quotes/delivery')).statusCode, 404);
  assert.equal(logs.some(entry => entry.level >= 50), false);
});

test('real PostgreSQL migration is repeatable; Redis PING, readiness and resource cleanup', { timeout: 15000 }, async t => {
  const url = new URL(env.DATABASE_URL);
  assert.ok(['127.0.0.1', 'localhost', 'postgres'].includes(url.hostname), 'Integration writes require a local PostgreSQL host');
  const migration = { databaseUrl: env.DATABASE_URL, dir: fileURLToPath(new URL('../../migrations', import.meta.url)), direction: 'up', migrationsTable: 'pgmigrations', log: () => {} };
  await runner(migration);
  assert.deepEqual(await runner(migration), []);
  const { app } = await createApplication(env, createLogger({ write() {} }));
  t.after(() => app.close());
  const database = app.get(DatabaseService);
  const redis = app.get(RedisService);
  const schema = await database.query('SELECT schema_name FROM information_schema.schemata WHERE schema_name = $1', ['monosfer']);
  assert.equal(schema.rows[0].schema_name, 'monosfer');
  const literal = "'; DROP SCHEMA monosfer; --";
  assert.equal((await database.query('SELECT $1::text AS value', [literal])).rows[0].value, literal);
  assert.equal(await redis.ping(), true);
  assert.equal((await app.inject('/v1/health/ready')).statusCode, 200);
  await redis.onApplicationShutdown();
  assert.equal((await app.inject('/v1/health/ready')).statusCode, 503);
  assert.equal((await app.inject('/v1/health/live')).statusCode, 200);
});

test('unreachable services yield bounded 503 without preventing liveness', { timeout: 10000 }, async t => {
  const { app } = await createApplication({ ...env, DATABASE_URL: 'postgresql://unused:SECRET@127.0.0.1:1/test', REDIS_URL: 'redis://127.0.0.1:1' }, createLogger({ write() {} }));
  t.after(() => app.close());
  const response = await app.inject('/v1/health/ready');
  assert.equal(response.statusCode, 503);
  assert.equal(response.body.includes('SECRET'), false);
  assert.equal((await app.inject('/v1/health/live')).statusCode, 200);
});
