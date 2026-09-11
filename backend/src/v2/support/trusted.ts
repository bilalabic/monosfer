import { createHash } from 'node:crypto';
import { ForbiddenException, ServiceUnavailableException } from '@nestjs/common';
import type { PoolClient } from 'pg';
import type { Settings } from '../config/config.js';
import type { Cursor } from '../indexer/store.js';
import { states } from '../indexer/events.js';
import type { PrivateRecord } from '../private-data/private-data.module.js';

export async function trustedStream(client: PoolClient, settings: Settings): Promise<Cursor> {
  const s = settings.indexer;
  if (!s.enabled || !s.deployment || !s.fingerprint) throw new ServiceUnavailableException();
  const row = (await client.query<Cursor>('SELECT * FROM monosfer.indexer_streams WHERE stream=$1 FOR SHARE',
    [`${s.chainId}:${s.deployment.address.toLowerCase()}`])).rows[0];
  if (!row || row.status !== 'ready' || !row.integrity_ok || row.last_block !== row.observed_head || row.export_fingerprint !== s.fingerprint ||
    !row.checked_at || Date.now() - row.checked_at.getTime() > s.staleSeconds * 1000) throw new ServiceUnavailableException();
  return row;
}
export async function trustedDelivery(client: PoolClient, settings: Settings, id: string, requirePrivate: boolean) {
  const cursor = await trustedStream(client, settings);
  const row = (await client.query(`SELECT data FROM monosfer.delivery_projections WHERE stream=$1 AND delivery_id=$2 AND updated_block<=$3 FOR SHARE`,
    [cursor.stream, id, cursor.last_block])).rows[0];
  if (!row || !states.slice(1).includes(row.data.state)) throw new ForbiddenException();
  const data = row.data as Record<string, string>;
  const record = (await client.query<PrivateRecord>(`SELECT p.* FROM monosfer.private_delivery_links l
    JOIN monosfer.private_delivery_records p ON p.id=l.private_record_id
    WHERE l.stream=$1 AND l.delivery_id=$2 AND l.quote_digest=$3 AND p.customer_wallet=$4 AND p.kind='delivery'
    FOR SHARE OF l,p`, [cursor.stream, id, data.quoteDigest, data.customer])).rows[0];
  if (requirePrivate && !record) throw new ForbiddenException();
  const binding = record ? createHash('sha256').update(JSON.stringify([cursor.stream,id,record.id,data.quoteDigest,data.customer,data.courier,settings.indexer.fingerprint])).digest('hex') : null;
  return { cursor, data, record, binding };
}
