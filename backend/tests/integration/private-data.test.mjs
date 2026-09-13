import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { ObjectId, MongoClient } from 'mongodb';
import { runner } from 'node-pg-migrate';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { PrivateDataCrypto, parsePrivateKey, recordAad } from '../../dist/private-data/crypto.js';
import { PrivateDataImporter, createImportPool } from '../../dist/private-data/importer.js';
import { authEnv } from '../support/env.mjs';
import { privateFixtures, fixtureItems, privateSecrets } from '../support/private-data.mjs';

const databaseUrl = process.env.DATABASE_URL ?? 'postgresql://monosfer:local-development-only@127.0.0.1:55432/monosfer_v2';
const readerUri = 'mongodb://legacy_reader:local-read-only@127.0.0.1:57017/monosfer_legacy_test';
async function cli(script, args, env) {
  const child = spawn(process.execPath, [fileURLToPath(new URL(`../../scripts/${script}`, import.meta.url)), ...args], {
    env: { ...process.env, ...authEnv, NODE_ENV: 'test', DATABASE_URL: databaseUrl, LEGACY_MONGODB_URI: readerUri,
      LEGACY_MONGODB_DATABASE: 'monosfer_legacy_test', LEGACY_MONGODB_READ_PREFERENCE: 'primary', ...env }, stdio: ['ignore', 'pipe', 'pipe'], timeout: 30000,
  });
  let output = '';
  child.stdout.on('data', chunk => { output += chunk; }); child.stderr.on('data', chunk => { output += chunk; });
  const [code] = await once(child, 'close');
  for (const secret of [...privateSecrets, 'local-read-only', 'local-development-only', readerUri]) assert.equal(output.includes(secret), false);
  return { code, output, events: output.trim().split('\n').filter(Boolean).map(line => JSON.parse(line)) };
}

test('real private import: read-only Mongo CLI, inventory, SQL, dry-run, concurrent rerun and recovery', { timeout: 120000 }, async t => {
  const target = new URL(databaseUrl);
  assert.ok(['127.0.0.1', 'localhost'].includes(target.hostname));
  assert.ok(['/monosfer_v2', '/monosfer_v2_test'].includes(target.pathname));
  const migration = { databaseUrl, dir: fileURLToPath(new URL('../../migrations', import.meta.url)), direction: 'up', migrationsTable: 'pgmigrations', log: () => {} };
  await runner(migration); assert.deepEqual(await runner(migration), []);
  const namespace = `fixture-${randomUUID()}`;
  const pool = createImportPool(databaseUrl);
  const admin = new MongoClient('mongodb://fixture_admin:local-fixtures-only@127.0.0.1:57017/admin', { serverSelectionTimeoutMS: 3000 });
  const db = admin.db('monosfer_legacy_test');
  const f = privateFixtures();
  const customerUser = { _id: new ObjectId(), walletAddress: f.customer, email: 'EXCLUDED_EMAIL' };
  const invalid = { ...f.delivery, _id: new ObjectId(), customer: 'PRIVATE_PHONE' };
  const ids = { deliveries: [f.delivery._id, invalid._id], disputes: [f.dispute._id], users: [f.user._id, customerUser._id] };
  const crypto = new PrivateDataCrypto(parsePrivateKey(authEnv));
  const importer = new PrivateDataImporter(pool, crypto);
  t.after(async () => {
    try {
      // Exact random fixtures from this test only. No truncate, drop, or source migration writes.
      for (const [collection, values] of Object.entries(ids)) await db.collection(collection).deleteMany({ _id: { $in: values } });
      await pool.query('DELETE FROM monosfer.private_data_import_items WHERE run_id IN (SELECT id FROM monosfer.private_data_import_runs WHERE source_namespace=$1)', [namespace]);
      await pool.query('DELETE FROM monosfer.private_delivery_records WHERE source_namespace=$1', [namespace]);
      await pool.query('DELETE FROM monosfer.private_data_import_runs WHERE source_namespace=$1', [namespace]);
    } finally { await admin.close(); await pool.end(); }
  });
  await db.collection('deliveries').insertMany([f.delivery, invalid]);
  await db.collection('disputes').insertOne(f.dispute);
  await db.collection('users').insertMany([f.user, customerUser]);
  const before = await Promise.all(Object.keys(ids).map(name => db.collection(name).find({ _id: { $in: ids[name] } }).sort({ _id: 1 }).toArray()));

  const reader = new MongoClient(readerUri);
  try {
    const privileges = await reader.db('monosfer_legacy_test').command({ connectionStatus: 1 });
    assert.deepEqual(privileges.authInfo.authenticatedUserRoles, [{ role: 'read', db: 'monosfer_legacy_test' }]);
  } finally { await reader.close(); }
  const cliEnv = { LEGACY_MONGODB_SOURCE_ID: namespace };
  const inventory = await cli('private-inventory.mjs', [], cliEnv);
  assert.equal(inventory.code, 0);
  assert.ok(inventory.events[0].report.counts.deliveries >= 2);
  assert.ok(inventory.events[0].report.walletMatches.matched >= 2);
  assert.ok(inventory.events[0].report.classifications['deliveries.INVALID_WALLET'] >= 1);
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM monosfer.private_data_import_runs WHERE source_namespace=$1', [namespace])).rows[0].n, 0);

  const dryRun = randomUUID();
  const dry = await cli('private-migrate.mjs', ['--dry-run', `--run-id=${dryRun}`], cliEnv);
  assert.equal(dry.code, 2); // Invalid fixture is reported explicitly, not hidden as success.
  assert.ok(dry.events.at(-1).report.validated >= 3);
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM monosfer.private_delivery_records WHERE source_namespace=$1', [namespace])).rows[0].n, 0);
  const runId = randomUUID();
  const apply = await cli('private-migrate.mjs', ['--apply', `--run-id=${runId}`], cliEnv);
  assert.equal(apply.code, 2); assert.ok(apply.events.at(-1).report.imported >= 3);
  const rows = (await pool.query('SELECT * FROM monosfer.private_delivery_records WHERE source_namespace=$1', [namespace])).rows;
  const delivery = rows.find(row => row.legacy_mongo_id === f.delivery._id.toHexString());
  assert.equal(delivery.source, 'legacy_mongo'); assert.equal(delivery.verification_status, 'legacy_unverified');
  assert.deepEqual(crypto.decrypt(delivery.encrypted_payload, recordAad(delivery)), JSON.parse(JSON.stringify({ pickup: f.delivery.pickup, dropoff: f.delivery.dropoff, notes: f.delivery.notes })));
  for (const secret of [...privateSecrets, 'EXCLUDED_EMAIL', 'EXCLUDED_PHONE']) assert.equal(JSON.stringify(rows).includes(secret), false);
  const dispute = rows.find(row => row.kind === 'dispute' && row.legacy_mongo_id === f.dispute._id.toHexString());
  assert.equal(dispute.parent_legacy_id, f.delivery._id.toHexString());
  assert.equal(crypto.decrypt(dispute.encrypted_payload, recordAad(dispute)).evidence[0].content, 'PRIVATE_EVIDENCE');
  const location = rows.find(row => row.kind === 'courier_location' && row.legacy_mongo_id === f.user._id.toHexString());
  assert.equal(crypto.decrypt(location.encrypted_payload, recordAad(location)).pushToken, 'PRIVATE_PUSH');
  const repeat = await cli('private-migrate.mjs', ['--apply'], cliEnv);
  assert.equal(repeat.code, 2); assert.ok(repeat.events.at(-1).report.skipped_existing >= 3);
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM monosfer.private_delivery_records WHERE source_namespace=$1', [namespace])).rows[0].n, rows.length);
  await assert.rejects(importer.run(fixtureItems(f), { runId, namespace, mode: 'dry_run' }), /Private data import failed/);

  // Independent concurrent runs collide only at the unique source identity; both retain item reports.
  const simultaneous = await Promise.all([1, 2].map(() => importer.run(fixtureItems(f), { runId: randomUUID(), namespace, mode: 'apply' })));
  for (const result of simultaneous) assert.equal(result.skipped_existing, 3);
  const resumedId = randomUUID();
  async function* interrupted() { yield { collection: 'deliveries', document: f.delivery }; throw new Error('PRIVATE_ADDRESS'); }
  await assert.rejects(importer.run(interrupted(), { runId: resumedId, namespace, mode: 'apply' }), /Private data import failed/);
  const resumed = await importer.run(fixtureItems(f), { runId: resumedId, namespace, mode: 'apply' });
  assert.equal(resumed.skipped_existing, 3);
  assert.deepEqual(await importer.run(fixtureItems(f), { runId: resumedId, namespace, mode: 'apply' }), resumed);
  // Per-item failure commits a fixed reason and subsequent items still proceed; retry heals the run.
  const failedId = randomUUID(); let failOnce = true;
  const failingCrypto = { decrypt: crypto.decrypt.bind(crypto), encrypt: (...args) => {
    if (failOnce) { failOnce = false; throw new Error('PRIVATE_ADDRESS'); }
    return crypto.encrypt(...args);
  } };
  const partial = await new PrivateDataImporter(pool, failingCrypto).run(fixtureItems(f), { runId: failedId, namespace, mode: 'apply' });
  assert.equal(partial.failed, 1); assert.equal(partial.skipped_existing, 2);
  const healed = await importer.run(fixtureItems(f), { runId: failedId, namespace, mode: 'apply' });
  assert.equal(healed.failed, undefined); assert.equal(healed.skipped_existing, 3);
  const lockId = randomUUID();
  let releaseSource; let sourceEntered;
  const waitSource = new Promise(resolve => { sourceEntered = resolve; });
  const holdSource = new Promise(resolve => { releaseSource = resolve; });
  async function* held() { sourceEntered(); await holdSource; yield { collection: 'deliveries', document: f.delivery }; }
  const active = importer.run(held(), { runId: lockId, namespace, mode: 'apply' });
  await waitSource;
  try { await assert.rejects(importer.run(fixtureItems(f), { runId: lockId, namespace, mode: 'apply' }), /Private data import failed/); }
  finally { releaseSource(); }
  assert.equal((await active).skipped_existing, 1);
  const after = await Promise.all(Object.keys(ids).map(name => db.collection(name).find({ _id: { $in: ids[name] } }).sort({ _id: 1 }).toArray()));
  assert.deepEqual(after, before, 'Importer and inventory never changed source documents');
  const missing = await cli('private-inventory.mjs', [], { ...cliEnv, LEGACY_MONGODB_URI: '' }); assert.equal(missing.code, 1);
  const down = await cli('private-migrate.mjs', ['--dry-run'], { ...cliEnv, LEGACY_MONGODB_URI: 'mongodb://secret:PRIVATE_PHONE@127.0.0.1:1' }); assert.equal(down.code, 1);
  const conflicting = await cli('private-migrate.mjs', ['--dry-run', '--apply'], cliEnv); assert.equal(conflicting.code, 1);
});
