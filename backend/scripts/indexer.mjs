import { loadBundle, parseIndexerSettings } from '../dist/indexer/config.js';
import { IndexerWorker } from '../dist/indexer/worker.js';
import { HubRpc } from '../dist/indexer/rpc.js';
import { createImportPool, assertImportTarget } from '../dist/private-data/importer.js';
import { setTimeout } from 'node:timers/promises';

let pool; const stop = new AbortController();
const shutdown = () => stop.abort();
process.once('SIGTERM', shutdown); process.once('SIGINT', shutdown);
try {
  const [command, ...args] = process.argv.slice(2);
  if (!['once','watch','replay','reconcile'].includes(command) || args.some(arg => arg !== '--confirm-production-indexing')) throw new Error();
  const settings = parseIndexerSettings(process.env);
  // All commands write cursor/audit/projections. No non-local writes without explicit operator flag.
  const url = assertImportTarget(process.env, 'apply', args.includes('--confirm-production-indexing'));
  pool = createImportPool(url);
  const worker = new IndexerWorker(pool, new HubRpc(settings.rpcUrl, stop.signal), loadBundle(), settings, stop.signal);
  if (command === 'watch') {
    let failures = 0;
    while (!stop.signal.aborted) {
      try { console.log(JSON.stringify({ event: 'indexer_batch', ...await worker.once() })); failures = 0; }
      catch { failures = Math.min(failures + 1, 5); console.error(JSON.stringify({ event: 'indexer_batch_failed' })); }
      try { await setTimeout(Math.min(settings.pollMs * 2 ** failures, 60000), undefined, { signal: stop.signal }); } catch { /* stop requested */ }
    }
  } else {
    const result = command === 'replay' ? await worker.replay() : command === 'reconcile' ? await worker.reconcile() : await worker.once();
    console.log(JSON.stringify({ event: `indexer_${command}_completed`, result }));
    if (result && 'mismatches' in result && result.mismatches) process.exitCode = 2;
  }
} catch { console.error(JSON.stringify({ event: 'indexer_operation_failed' })); process.exitCode = 1; }
finally { if (pool) await pool.end(); process.removeListener('SIGTERM', shutdown); process.removeListener('SIGINT', shutdown); }
