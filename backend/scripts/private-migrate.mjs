import { randomUUID } from 'node:crypto';
import { LegacySource, parseLegacySettings } from '../dist/private-data/legacy-source.js';
import { parsePrivateKey, PrivateDataCrypto } from '../dist/private-data/crypto.js';
import { assertImportTarget, createImportPool, PrivateDataImporter } from '../dist/private-data/importer.js';

let source; let pool; let runId;
try {
  const args = process.argv.slice(2);
  const allowed = ['--dry-run', '--apply', '--confirm-production-import'];
  if (args.some(arg => !allowed.includes(arg) && !/^--run-id=[0-9a-f-]{36}$/i.test(arg)) || new Set(args).size !== args.length ||
      Number(args.includes('--dry-run')) + Number(args.includes('--apply')) !== 1 || args.filter(arg => arg.startsWith('--run-id=')).length > 1) throw new Error();
  const mode = args.includes('--apply') ? 'apply' : 'dry_run';
  const connectionString = assertImportTarget(process.env, mode, args.includes('--confirm-production-import'));
  const settings = parseLegacySettings(process.env);
  const crypto = new PrivateDataCrypto(parsePrivateKey(process.env));
  runId = args.find(arg => arg.startsWith('--run-id='))?.slice(9) ?? randomUUID();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(runId)) throw new Error();
  source = new LegacySource(settings);
  pool = createImportPool(connectionString);
  console.log(JSON.stringify({ event: 'private_import_started', runId, mode }));
  const report = await new PrivateDataImporter(pool, crypto).run(source.items(), { runId, namespace: settings.namespace, mode });
  console.log(JSON.stringify({ event: 'private_import_result', runId, report }));
  if (report.invalid || report.failed || report.pending) process.exitCode = 2;
} catch {
  console.error(JSON.stringify({ event: 'private_import_failed', runId }));
  process.exitCode = 1;
} finally {
  if (source) await source.close();
  if (pool) await pool.end();
}
