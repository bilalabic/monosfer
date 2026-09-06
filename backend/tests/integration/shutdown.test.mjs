import test from 'node:test';
import assert from 'node:assert/strict';
import { fork } from 'node:child_process';
import { once } from 'node:events';

for (const signal of ['SIGTERM', 'SIGINT']) {
  test(`${signal} drains HTTP and closes real PostgreSQL/Redis before process exit`, { timeout: 90000 }, async t => {
    const startedAt = Date.now();
    const child = fork(new URL('../support/shutdown-child.mjs', import.meta.url), [], {
      silent: true,
      env: {
        ...process.env, NODE_ENV: 'test', CORS_ORIGINS: 'http://localhost:3000',
        DATABASE_URL: process.env.DATABASE_URL ?? 'postgresql://monosfer:local-development-only@127.0.0.1:55432/monosfer_v2',
        REDIS_URL: process.env.REDIS_URL ?? 'redis://:local-development-only@127.0.0.1:56379',
      },
    });
    t.after(() => { if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL'); });
    let output = '';
    child.stdout.on('data', chunk => { output += chunk; });
    child.stderr.on('data', chunk => { output += chunk; });
    const closed = once(child, 'close');
    const ready = await Promise.race([once(child, 'message'), closed.then(() => { throw new Error(`Child failed before ready: ${output}`); })]);
    assert.equal(ready[0].ready, true);
    t.diagnostic(`Child bootstrap: ${Date.now() - startedAt}ms; shutdown deadline: 5000ms`);
    let timer;
    const deadline = new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(`Shutdown timed out: ${output}`)), 5000); });
    t.after(() => clearTimeout(timer));
    child.send(signal);
    await Promise.race([closed, deadline]);
    assert.match(output, /"closed":"postgres"/);
    assert.match(output, /"closed":"redis"/);
  });
}
