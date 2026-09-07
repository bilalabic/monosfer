import { createHash, randomUUID } from 'node:crypto';
import { BSON } from 'mongodb';
import { Pool, type PoolClient } from 'pg';
import { PrivateDataCrypto, recordAad } from './crypto.js';
import { mapLegacy, MappingError } from './mapping.js';
import { safeLegacyId, type SourceItem } from './legacy-source.js';

export type ImportMode = 'dry_run' | 'apply';
export interface ImportOptions { runId: string; namespace: string; mode: ImportMode }
export function assertImportTarget(env: NodeJS.ProcessEnv, mode: ImportMode, confirmProduction: boolean): string {
  try {
    const url = new URL(env.DATABASE_URL ?? '');
    if (!['postgres:', 'postgresql:'].includes(url.protocol) || !url.hostname) throw new Error();
    const local = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname) && ['/monosfer_v2', '/monosfer_v2_test'].includes(url.pathname);
    // A dry-run also writes its audit report. Guard remote destinations in both modes.
    if ((!local || env.NODE_ENV === 'production') && !confirmProduction) throw new Error();
    if (!['dry_run', 'apply'].includes(mode)) throw new Error();
    return url.href;
  } catch { throw new Error('Import target requires a local development/test database or --confirm-production-import'); }
}
export function createImportPool(connectionString: string): Pool {
  const pool = new Pool({ connectionString, max: 2, connectionTimeoutMillis: 5000, statement_timeout: 10000, query_timeout: 12000 });
  pool.on('error', () => {});
  return pool;
}
export class PrivateDataImporter {
  constructor(private readonly pool: Pool, private readonly crypto: PrivateDataCrypto) {}
  private async report(client: PoolClient, id: string) {
    const result = await client.query<{ status: string; count: number }>('SELECT status, count(*)::integer AS count FROM monosfer.private_data_import_items WHERE run_id = $1 GROUP BY status', [id]);
    return Object.fromEntries(result.rows.map(row => [row.status, row.count]));
  }
  async run(source: AsyncIterable<SourceItem>, options: ImportOptions): Promise<Record<string, number>> {
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(options.runId) ||
      !/^[a-zA-Z0-9_-]{1,64}$/.test(options.namespace) || !['apply', 'dry_run'].includes(options.mode)) throw new Error('Invalid import options');
    const client = await this.pool.connect();
    let locked = false;
    let started = false;
    try {
      // Session lock is released on disconnect/crash; item commits survive interruption.
      locked = (await client.query('SELECT pg_try_advisory_lock(hashtextextended($1, 0)) AS locked', [`private-import:${options.runId}`])).rows[0].locked === true;
      if (!locked) throw new Error('Import run already active');
      await client.query(`INSERT INTO monosfer.private_data_import_runs (id, source_namespace, mode, status) VALUES ($1,$2,$3,'running') ON CONFLICT DO NOTHING`, [options.runId, options.namespace, options.mode]);
      const run = (await client.query('SELECT * FROM monosfer.private_data_import_runs WHERE id = $1', [options.runId])).rows[0];
      if (run.source_namespace !== options.namespace || run.mode !== options.mode || run.mapping_version !== 1) throw new Error('Import run options mismatch');
      if (run.status === 'completed') return await this.report(client, options.runId);
      await client.query("UPDATE monosfer.private_data_import_runs SET status = 'running', updated_at = now() WHERE id = $1", [options.runId]);
      started = true;
      for await (const item of source) {
        const id = safeLegacyId(item.document);
        // Invalid ids are correlated with a hash, never persisted/logged as arbitrary source text.
        const key = createHash('sha256').update(BSON.serialize({ id: item.document._id })).digest('hex');
        const args = [options.runId, item.collection, key];
        const previous = await client.query('SELECT status FROM monosfer.private_data_import_items WHERE run_id=$1 AND source_collection=$2 AND source_key=$3', args);
        if (['imported', 'skipped_existing', 'validated', 'skipped_no_private'].includes(previous.rows[0]?.status)) continue;
        await client.query(`INSERT INTO monosfer.private_data_import_items (run_id, source_collection, source_key, legacy_mongo_id, status)
          VALUES ($1,$2,$3,$4,'pending') ON CONFLICT (run_id,source_collection,source_key) DO UPDATE SET status='pending', reason_code=NULL, updated_at=now()`, [...args, id]);
        try {
          const mapped = mapLegacy(item.collection, item.document, item.parent);
          if (!mapped) {
            await client.query("UPDATE monosfer.private_data_import_items SET status='skipped_no_private', updated_at=now() WHERE run_id=$1 AND source_collection=$2 AND source_key=$3", args);
            continue;
          }
          const recordId = randomUUID();
          const context = { id: recordId, source_namespace: options.namespace, source_collection: item.collection,
            legacy_mongo_id: mapped.legacyId, kind: mapped.kind, schema_version: 1 };
          const encrypted = this.crypto.encrypt(mapped.payload, recordAad(context));
          // Exercises authentication and serialization in dry-run as well as apply.
          this.crypto.decrypt(encrypted, recordAad(context));
          await client.query('BEGIN');
          let status = 'validated';
          let targetId: string | null = null;
          if (options.mode === 'apply') {
            const inserted = await client.query(`INSERT INTO monosfer.private_delivery_records
              (id,source_namespace,source_collection,legacy_mongo_id,parent_legacy_id,kind,customer_wallet,courier_wallet,legacy_status,metadata,encrypted_payload,import_run_id)
              VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
              ON CONFLICT (source_namespace,source_collection,legacy_mongo_id) DO NOTHING RETURNING id`,
            [recordId, options.namespace, item.collection, mapped.legacyId, mapped.parentLegacyId, mapped.kind, mapped.customer, mapped.courier,
              mapped.status, JSON.stringify(mapped.metadata), JSON.stringify(encrypted), options.runId]);
            status = inserted.rowCount ? 'imported' : 'skipped_existing';
            targetId = inserted.rows[0]?.id ?? (await client.query('SELECT id FROM monosfer.private_delivery_records WHERE source_namespace=$1 AND source_collection=$2 AND legacy_mongo_id=$3', [options.namespace, item.collection, mapped.legacyId])).rows[0].id;
          }
          await client.query('UPDATE monosfer.private_data_import_items SET status=$4, record_id=$5, updated_at=now() WHERE run_id=$1 AND source_collection=$2 AND source_key=$3', [...args, status, targetId]);
          await client.query('COMMIT');
        } catch (error) {
          await client.query('ROLLBACK');
          const invalid = error instanceof MappingError;
          await client.query('UPDATE monosfer.private_data_import_items SET status=$4, reason_code=$5, updated_at=now() WHERE run_id=$1 AND source_collection=$2 AND source_key=$3',
            [...args, invalid ? 'invalid' : 'failed', invalid ? error.code : 'IMPORT_FAILED']);
        }
      }
      const report = await this.report(client, options.runId);
      await client.query('UPDATE monosfer.private_data_import_runs SET status=$2, updated_at=now() WHERE id=$1',
        [options.runId, report.invalid || report.failed || report.pending ? 'completed_with_errors' : 'completed']);
      return report;
    } catch {
      if (started) await client.query("UPDATE monosfer.private_data_import_runs SET status='failed', updated_at=now() WHERE id=$1", [options.runId]).catch(() => {});
      throw new Error('Private data import failed');
    } finally {
      let discard = false;
      if (locked) try {
        await client.query('SELECT pg_advisory_unlock(hashtextextended($1, 0))', [`private-import:${options.runId}`]);
      } catch { discard = true; }
      client.release(discard);
    }
  }
}
