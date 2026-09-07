import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { once } from 'node:events';
import { fileURLToPath } from 'node:url';
import { authEnv } from '../support/env.mjs';

async function startup(env, t) {
  const child = spawn(process.execPath, [fileURLToPath(new URL('../../dist/main.js', import.meta.url))], { env, stdio: ['ignore', 'pipe', 'pipe'] });
  t.after(() => { if (child.exitCode === null) child.kill('SIGKILL'); });
  let output = '';
  child.stdout.on('data', chunk => { output += chunk; });
  child.stderr.on('data', chunk => { output += chunk; });
  const [code] = await once(child, 'close');
  return { code, output };
}

test('production entrypoint fails config validation without leaking secrets', { timeout: 10000 }, async t => {
  const { code, output } = await startup({ ...process.env, NODE_ENV: 'production', DATABASE_URL: 'https://PRIVATE_SECRET@localhost', REDIS_URL: '', CORS_ORIGINS: 'http://localhost:3000' }, t);
  assert.equal(code, 1);
  assert.match(output, /backend_start_failed/);
  assert.equal(output.includes('PRIVATE_SECRET'), false);
});

test('occupied HTTP port closes infrastructure and exits rather than hanging', { timeout: 10000 }, async t => {
  const listener = createServer();
  listener.listen(0, '127.0.0.1');
  await once(listener, 'listening');
  t.after(() => listener.close());
  const { code, output } = await startup({
    ...process.env, ...authEnv, NODE_ENV: 'production', HOST: '127.0.0.1', PORT: String(listener.address().port),
    DATABASE_URL: process.env.DATABASE_URL ?? 'postgresql://monosfer:local-development-only@127.0.0.1:55432/monosfer_v2',
    REDIS_URL: process.env.REDIS_URL ?? 'redis://:local-development-only@127.0.0.1:56379',
    CORS_ORIGINS: 'https://app.example.com',
  }, t);
  assert.equal(code, 1);
  assert.match(output, /backend_start_failed/);
});
