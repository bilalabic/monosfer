import type { Pool, PoolClient } from 'pg';
import type { Bundle, Deployment, IndexerSettings } from './config.js';
import type { IndexerRpc } from './rpc.js';
import { decodeLogs, states, type ChainBlock } from './events.js';
import { applyBatch, cursor, projection, replayDelivery, reconstructDelivery, transaction, type Cursor } from './store.js';

function stableJson(value: unknown): string {
  return JSON.stringify(value, (_key, v) => v && typeof v === 'object' && !Array.isArray(v)
    ? Object.fromEntries(Object.entries(v).sort(([a], [b]) => a.localeCompare(b))) : v);
}

export class IndexerWorker {
  readonly stream: string;
  readonly deployment: Deployment;
  constructor(private readonly pool: Pool, private readonly rpc: IndexerRpc, private readonly bundle: Bundle, private readonly settings: IndexerSettings, private readonly signal?: AbortSignal) {
    const deployment = bundle.chains[settings.chainId];
    if (!settings.enabled || !deployment || !Number.isSafeInteger(deployment.block) || deployment.block < 1 || !/^0x[0-9a-fA-F]{40}$/.test(deployment.address)) throw new Error('Invalid indexer deployment');
    this.deployment = { ...deployment, address: deployment.address.toLowerCase() as Deployment['address'] };
    this.stream = `${settings.chainId}:${this.deployment.address}`;
  }
  private async lease<T>(work: (db: PoolClient) => Promise<T>): Promise<T> {
    const db = await this.pool.connect(); let locked = false; let discard = false;
    try {
      locked = (await db.query('SELECT pg_try_advisory_lock(hashtextextended($1,0)) AS locked', [`indexer:${this.stream}`])).rows[0].locked;
      if (!locked) throw new Error('Indexer is already active');
      this.signal?.throwIfAborted();
      return await work(db);
    } catch {
      if (locked) await db.query("UPDATE monosfer.indexer_streams SET status='error' WHERE stream=$1", [this.stream]).catch(() => {});
      throw new Error('Indexer operation failed');
    } finally {
      if (locked) try { await db.query('SELECT pg_advisory_unlock(hashtextextended($1,0))', [`indexer:${this.stream}`]); } catch { discard = true; }
      db.release(discard);
    }
  }
  private async initialize(db: PoolClient): Promise<Cursor> {
    if (await this.rpc.chainId() !== this.settings.chainId) throw new Error('RPC chain mismatch');
    const code = await this.rpc.code(this.deployment.address);
    if (!code || code === '0x') throw new Error('Missing deployed contract');
    let current = await cursor(db, this.stream);
    if (!current) {
      const anchor = await this.rpc.block(BigInt(this.deployment.block) - 1n);
      await transaction(db, async () => {
        await db.query(`INSERT INTO monosfer.indexer_streams(stream,chain_id,contract_address,export_fingerprint,start_block,last_block,last_hash,observed_head,status)
          VALUES($1,$2,$3,$4,$5,$6,$7,$6,'syncing')`, [this.stream, this.settings.chainId, this.deployment.address, this.bundle.fingerprint, this.deployment.block, anchor.number.toString(), anchor.hash]);
        await applyBatch(db, this.stream, [anchor], []);
      });
      current = await cursor(db, this.stream);
    }
    if (current!.export_fingerprint !== this.bundle.fingerprint || BigInt(current!.start_block) !== BigInt(this.deployment.block)) throw new Error('Export changed; reviewed migration required');
    return current!;
  }
  private async canonical(db: PoolClient, current: Cursor): Promise<Cursor> {
    const tip = await this.rpc.block(BigInt(current.last_block));
    if (tip.hash === current.last_hash) return current;
    const floor = BigInt(current.start_block) - 1n;
    let ancestor: ChainBlock | undefined;
    for (let depth = 1n; depth <= BigInt(this.settings.reorgDepth) && BigInt(current.last_block) - depth >= floor; depth++) {
      this.signal?.throwIfAborted();
      const height = BigInt(current.last_block) - depth;
      const known = (await db.query('SELECT hash FROM monosfer.indexer_blocks WHERE stream=$1 AND number=$2 AND canonical', [this.stream, height.toString()])).rows[0];
      const block = await this.rpc.block(height);
      if (known?.hash === block.hash) { ancestor = block; break; }
    }
    if (!ancestor) throw new Error('Reorg exceeds recovery window');
    const boundary = ancestor;
    await transaction(db, async () => {
      const affected = await db.query('SELECT DISTINCT delivery_id::text FROM monosfer.chain_event_inbox WHERE stream=$1 AND canonical AND block_number>$2 AND delivery_id IS NOT NULL', [this.stream, boundary.number.toString()]);
      await db.query('UPDATE monosfer.chain_event_inbox SET canonical=false WHERE stream=$1 AND block_number>$2 AND canonical', [this.stream, boundary.number.toString()]);
      await db.query('UPDATE monosfer.indexer_blocks SET canonical=false WHERE stream=$1 AND number>$2 AND canonical', [this.stream, boundary.number.toString()]);
      for (const row of affected.rows) await replayDelivery(db, this.stream, row.delivery_id, boundary.number);
      await db.query("UPDATE monosfer.indexer_streams SET last_block=$2,last_hash=$3,status='syncing',checked_at=NULL,reconciled_at=NULL WHERE stream=$1", [this.stream, boundary.number.toString(), boundary.hash]);
    });
    return (await cursor(db, this.stream))!;
  }
  async once(): Promise<{ indexedBlock: string; finalizedBlock: string }> {
    return this.lease(async db => {
      let current = await this.initialize(db);
      if (!current.integrity_ok) throw new Error('Reconciliation required');
      await db.query("UPDATE monosfer.indexer_streams SET status='syncing',checked_at=NULL WHERE stream=$1", [this.stream]);
      const head = await this.rpc.block('finalized');
      if (head.number < BigInt(current.last_block)) throw new Error('Finalized head regressed');
      current = await this.canonical(db, current);
      const from = BigInt(current.last_block) + 1n;
      const end = from + BigInt(this.settings.batchSize) - 1n;
      const to = end < head.number ? end : head.number;
      if (from <= to) {
        const blocks: ChainBlock[] = [];
        for (let number = from; number <= to;) {
          this.signal?.throwIfAborted();
          const work: Promise<ChainBlock>[] = [];
          for (let i = 0; i < 8 && number <= to; i++, number++) work.push(this.rpc.block(number));
          blocks.push(...await Promise.all(work));
        }
        for (let i = 0; i < blocks.length; i++) {
          if (blocks[i]!.number !== from + BigInt(i) || blocks[i]!.parentHash !== (i ? blocks[i - 1]!.hash : current.last_hash)) throw new Error('Noncontiguous RPC chain');
        }
        const events = decodeLogs(this.bundle.abi, this.deployment.address, blocks, await this.rpc.logs(this.deployment.address, from, to));
        if ((await this.rpc.block(to)).hash !== blocks.at(-1)!.hash) throw new Error('RPC changed during fetch');
        if ((await this.rpc.block(head.number)).hash !== head.hash) throw new Error('Finalized checkpoint changed');
        await transaction(db, async () => {
          await applyBatch(db, this.stream, blocks, events);
          await db.query('UPDATE monosfer.indexer_streams SET last_block=$2,last_hash=$3 WHERE stream=$1', [this.stream, to.toString(), blocks.at(-1)!.hash]);
        });
      }
      await db.query("UPDATE monosfer.indexer_streams SET observed_head=$2,checked_at=now(),status=CASE WHEN last_block=$2 THEN 'ready' ELSE 'syncing' END WHERE stream=$1", [this.stream, head.number.toString()]);
      return { indexedBlock: (await cursor(db, this.stream))!.last_block, finalizedBlock: head.number.toString() };
    });
  }
  async replay(): Promise<void> {
    await this.lease(async db => {
      const current = await this.initialize(db);
      await db.query("UPDATE monosfer.indexer_streams SET status='replaying' WHERE stream=$1", [this.stream]);
      await transaction(db, async () => {
        const ids = await db.query(`SELECT delivery_id::text FROM monosfer.delivery_projections WHERE stream=$1 UNION
          SELECT delivery_id::text FROM monosfer.chain_event_inbox WHERE stream=$1 AND canonical AND delivery_id IS NOT NULL`, [this.stream]);
        for (const row of ids.rows) { this.signal?.throwIfAborted(); await replayDelivery(db, this.stream, row.delivery_id, BigInt(current.last_block)); }
        await db.query("UPDATE monosfer.indexer_streams SET status='syncing',checked_at=NULL,reconciled_at=NULL,integrity_ok=false WHERE stream=$1", [this.stream]);
      });
    });
  }
  async reconcile(): Promise<{ checkedDeliveries: number; checkedBids: number; mismatches: number }> {
    return this.lease(async db => {
      const current = await this.initialize(db);
      if ((await this.rpc.block(BigInt(current.last_block))).hash !== current.last_hash) throw new Error('Noncanonical checkpoint');
      await db.query("UPDATE monosfer.indexer_streams SET status='reconciling' WHERE stream=$1", [this.stream]);
      const checkpoint = BigInt(current.last_block);
      const ids = (await db.query('SELECT delivery_id::text FROM monosfer.delivery_projections WHERE stream=$1 ORDER BY delivery_id', [this.stream])).rows;
      let mismatches = 0; let checkedBids = 0;
      // Compare canonical inbox with a fresh bounded log scan, including events for previously unseen bidders.
      for (let from = BigInt(current.start_block); from <= checkpoint; from += BigInt(this.settings.batchSize)) {
        this.signal?.throwIfAborted();
        const end = from + BigInt(this.settings.batchSize) - 1n;
        const to = end < checkpoint ? end : checkpoint;
        const storedBlocks = await db.query('SELECT number,hash,parent_hash FROM monosfer.indexer_blocks WHERE stream=$1 AND canonical AND number BETWEEN $2 AND $3 ORDER BY number', [this.stream, from.toString(), to.toString()]);
        const blocks = storedBlocks.rows.map(row => ({ number: BigInt(row.number), hash: row.hash, parentHash: row.parent_hash }));
        if (BigInt(blocks.length) !== to - from + 1n) throw new Error('Missing canonical block');
        const fresh = decodeLogs(this.bundle.abi, this.deployment.address, blocks, await this.rpc.logs(this.deployment.address, from, to));
        const stored = await db.query('SELECT event_name,args,raw_log FROM monosfer.chain_event_inbox WHERE stream=$1 AND canonical AND block_number BETWEEN $2 AND $3 ORDER BY block_number,transaction_index,log_index', [this.stream, from.toString(), to.toString()]);
        const normalized = fresh.map(e => ({ event_name: e.name, args: e.args, raw_log: { ...e.log, blockNumber: e.log.blockNumber.toString() } }));
        if (stableJson(normalized) !== stableJson(stored.rows)) mismatches++;
      }
      const total = await this.rpc.read(this.deployment.address, this.bundle.abi, 'nextDeliveryId', [], checkpoint);
      if (BigInt(String(total)) !== BigInt(ids.length)) mismatches++;
      for (const row of ids) {
        this.signal?.throwIfAborted();
        const p = await projection(db, this.stream, row.delivery_id);
        const replayed = await transaction(db, () => reconstructDelivery(db, this.stream, row.delivery_id));
        if (stableJson(p) !== stableJson(replayed)) mismatches++;
        const onchain = await this.rpc.read(this.deployment.address, this.bundle.abi, 'deliveryOf', [BigInt(row.delivery_id)], checkpoint) as Record<string, unknown>;
        for (const [key, value] of Object.entries(onchain)) {
          const expected = key === 'state' ? states[Number(value)] : typeof value === 'string' ? value.toLowerCase() : String(value);
          if (String(p.delivery?.[key as keyof typeof p.delivery]) !== String(expected)) { mismatches++; break; }
        }
        for (const bid of Object.values(p.bids)) {
          const chainBid = await this.rpc.read(this.deployment.address, this.bundle.abi, 'bidOf', [BigInt(row.delivery_id), bid.courier], checkpoint) as Record<string, unknown>;
          if (Object.entries(chainBid).some(([key, value]) => String(bid[key as keyof typeof bid]) !== String(value))) mismatches++;
          checkedBids++;
        }
      }
      if ((await this.rpc.block(checkpoint)).hash !== current.last_hash) throw new Error('Checkpoint changed during reconciliation');
      await db.query("UPDATE monosfer.indexer_streams SET status=$2,reconciled_at=now(),checked_at=NULL,integrity_ok=$3 WHERE stream=$1", [this.stream, mismatches ? 'error' : 'syncing', mismatches === 0]);
      return { checkedDeliveries: ids.length, checkedBids, mismatches };
    });
  }
}
