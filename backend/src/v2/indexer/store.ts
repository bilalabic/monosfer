import type { PoolClient } from 'pg';
import type { ChainBlock, HubEvent, Projection, Delivery, Bid, ChainLog } from './events.js';
import { reduceEvent } from './events.js';

export const json = (value: unknown) => JSON.stringify(value, (_key, v) => typeof v === 'bigint' ? v.toString() : v);
export interface Cursor {
  stream: string; chain_id: number; contract_address: string; export_fingerprint: string; start_block: string;
  last_block: string; last_hash: string; observed_head: string; status: string; checked_at: Date | null;
  integrity_ok: boolean;
}
export async function cursor(db: PoolClient, stream: string): Promise<Cursor | undefined> {
  return (await db.query<Cursor>('SELECT * FROM monosfer.indexer_streams WHERE stream=$1', [stream])).rows[0];
}
export async function projection(db: PoolClient, stream: string, id: string): Promise<Projection> {
  const d = await db.query<{ data: Delivery }>('SELECT data FROM monosfer.delivery_projections WHERE stream=$1 AND delivery_id=$2', [stream, id]);
  const b = await db.query<{ courier: string; data: Bid }>('SELECT courier,data FROM monosfer.bid_projections WHERE stream=$1 AND delivery_id=$2', [stream, id]);
  return { delivery: d.rows[0]?.data ?? null, bids: Object.fromEntries(b.rows.map(row => [row.courier, row.data])) };
}
async function save(db: PoolClient, stream: string, id: string, p: Projection, block: bigint) {
  if (!p.delivery) {
    await db.query('DELETE FROM monosfer.bid_projections WHERE stream=$1 AND delivery_id=$2', [stream, id]);
    await db.query('DELETE FROM monosfer.delivery_projections WHERE stream=$1 AND delivery_id=$2', [stream, id]);
    return;
  }
  if (p.delivery.state === 'None') throw new Error('Incomplete creation events');
  await db.query(`INSERT INTO monosfer.delivery_projections(stream,delivery_id,data,updated_block) VALUES($1,$2,$3,$4)
    ON CONFLICT(stream,delivery_id) DO UPDATE SET data=excluded.data,updated_block=excluded.updated_block`, [stream, id, json(p.delivery), block.toString()]);
  await db.query('DELETE FROM monosfer.bid_projections WHERE stream=$1 AND delivery_id=$2 AND NOT (courier=ANY($3::text[]))', [stream, id, Object.keys(p.bids)]);
  await db.query(`INSERT INTO monosfer.bid_projections(stream,delivery_id,courier,data)
    SELECT $1,$2,value->>'courier',value FROM jsonb_array_elements($3::jsonb)
    ON CONFLICT(stream,delivery_id,courier) DO UPDATE SET data=excluded.data
    WHERE monosfer.bid_projections.data IS DISTINCT FROM excluded.data`, [stream, id, json(Object.values(p.bids))]);
}
export async function applyBatch(db: PoolClient, stream: string, blocks: ChainBlock[], events: HubEvent[]) {
  for (const block of blocks) {
    if (typeof block.timestamp !== 'bigint') throw new Error('Block timestamp required; reindex');
    await db.query(`INSERT INTO monosfer.indexer_blocks(stream,number,hash,parent_hash,canonical,timestamp) VALUES($1,$2,$3,$4,true,$5)
    ON CONFLICT(stream,hash) DO UPDATE SET canonical=true,timestamp=excluded.timestamp`, [stream, block.number.toString(), block.hash, block.parentHash, String(block.timestamp)]);
  }
  const changed = new Map<string, Projection>();
  for (const event of events) {
    const log = event.log;
    await db.query(`INSERT INTO monosfer.chain_event_inbox(stream,block_hash,block_number,transaction_hash,transaction_index,log_index,event_name,delivery_id,args,raw_log,canonical)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,true) ON CONFLICT(stream,block_hash,log_index) DO UPDATE SET canonical=true`,
    [stream, log.blockHash, log.blockNumber.toString(), log.transactionHash, log.transactionIndex, log.logIndex, event.name, event.args.deliveryId ?? null, json(event.args), json(log)]);
    const id = event.args.deliveryId;
    if (id === undefined) continue;
    if (!changed.has(id)) changed.set(id, await projection(db, stream, id));
    reduceEvent(changed.get(id)!, event);
  }
  for (const [id, p] of changed) await save(db, stream, id, p, blocks.at(-1)!.number);
}
export async function replayDelivery(db: PoolClient, stream: string, id: string, lastBlock: bigint) {
  await save(db, stream, id, await reconstructDelivery(db, stream, id), lastBlock);
}
export async function reconstructDelivery(db: PoolClient, stream: string, id: string): Promise<Projection> {
  const p: Projection = { delivery: null, bids: {} };
  // Server cursor bounds event memory for long-lived deliveries.
  await db.query(`DECLARE replay_events NO SCROLL CURSOR FOR SELECT e.event_name,e.args,e.raw_log,b.timestamp FROM monosfer.chain_event_inbox e
    JOIN monosfer.indexer_blocks b ON b.stream=e.stream AND b.hash=e.block_hash
    WHERE e.stream=$1 AND e.delivery_id=$2 AND e.canonical ORDER BY e.block_number,e.transaction_index,e.log_index`, [stream, id]);
  try {
    while (true) {
      const batch = await db.query('FETCH 500 FROM replay_events');
      if (!batch.rows.length) break;
      for (const row of batch.rows) {
        if (row.timestamp === null) throw new Error('Block timestamp required; reindex');
        reduceEvent(p, { name: row.event_name, args: row.args, timestamp: BigInt(row.timestamp), log: { ...row.raw_log, blockNumber: BigInt(row.raw_log.blockNumber) } as ChainLog });
      }
    }
  } finally { await db.query('CLOSE replay_events'); }
  return p;
}
export async function transaction<T>(db: PoolClient, work: () => Promise<T>): Promise<T> {
  await db.query('BEGIN');
  try { const result = await work(); await db.query('COMMIT'); return result; }
  catch (error) { await db.query('ROLLBACK'); throw error; }
}
