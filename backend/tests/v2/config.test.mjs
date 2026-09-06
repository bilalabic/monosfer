import test from 'node:test';
import assert from 'node:assert/strict';
import { parseSettings } from '../../dist/config/config.js';
import { testEnv } from '../support/app.mjs';

test('configuration defaults and explicit proxy flag', () => {
  const config = parseSettings(testEnv);
  assert.equal(config.port, 3001);
  assert.equal(config.trustProxy, false);
  assert.equal(parseSettings({ ...testEnv, TRUST_PROXY: 'true' }).trustProxy, true);
});

for (const [key, value] of [
  ['DATABASE_URL', ''], ['DATABASE_URL', 'https://secret:password@db'], ['REDIS_URL', 'bad-secret-url'],
  ['CORS_ORIGINS', '*'], ['CORS_ORIGINS', 'https://example.com/path'], ['CORS_ORIGINS', ''],
  ['PORT', '0'], ['PORT', '65536'], ['PORT', '3.1'], ['TRUST_PROXY', '1'], ['NODE_ENV', 'staging'],
  ['BODY_LIMIT_BYTES', '0'], ['CONNECTION_TIMEOUT_MS', 'Infinity'], ['HOST', ''],
]) {
  test(`reject invalid ${key} (${value}) without echoing input`, () => {
    assert.throws(() => parseSettings({ ...testEnv, [key]: value }), { message: `Invalid ${key}` });
  });
}
