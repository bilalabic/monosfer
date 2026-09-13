import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import type { PoolClient } from 'pg';
import { ConfigService, type Settings } from '../config/config.js';
import { DatabaseService } from '../infrastructure/database.module.js';
import { trustedStream } from '../support/trusted.js';

export function requireLocalOperations(settings: Settings) {
  if (settings.environment==='production' || !['localhost','127.0.0.1','[::1]'].includes(new URL(settings.databaseUrl).hostname) ||
    !['/monosfer_v2','/monosfer_v2_test','/test'].includes(new URL(settings.databaseUrl).pathname)) throw new Error('Local development/test database required');
}
@Injectable()
export class ReputationService {
  constructor(private readonly db: DatabaseService,private readonly config: ConfigService) {}
  async read(wallet: string, client?: PoolClient): Promise<unknown> {
    if(!client) { try { return await this.db.transaction(c=>this.read(wallet,c)); } catch { throw new ServiceUnavailableException(); } }
    const cursor=await trustedStream(client,this.config.settings);
    const row=(await client.query(`SELECT r.counters,r.rebuilt_at FROM monosfer.reputation_projections r
      JOIN monosfer.referral_reward_projections p ON p.stream=r.stream AND p.wallet=r.wallet
      WHERE r.stream=$1 AND r.wallet=$2 AND r.source_block=$3 AND r.source_hash=$4 AND r.export_fingerprint=$5
      AND p.source_block=r.source_block AND p.source_hash=r.source_hash AND p.export_fingerprint=r.export_fingerprint`,
      [cursor.stream,wallet.toLowerCase(),cursor.last_block,cursor.last_hash,cursor.export_fingerprint])).rows[0];
    return {wallet:wallet.toLowerCase(),status:row?'ready':'rebuild_pending',counters:row?.counters??null,
      source:'backend_delivery_projection',onChainReputation:{status:'export_missing'},
      sourceBlock:cursor.last_block,rebuiltAt:row?.rebuilt_at??null,referral:{status:'pending_policy'},reward:{status:'pending_policy'}};
  }
  async rebuild(apply: boolean) {
    if(apply) requireLocalOperations(this.config.settings);
    const start=Date.now();
    return this.db.transaction(async client=>{
      const cursor=await trustedStream(client,this.config.settings);
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[`reputation:${cursor.stream}`]);
      // Current-state counters, not invented scores. One role observation per finalized delivery.
      const rows=(await client.query(`WITH observations AS (
        SELECT data->>'customer' AS wallet,'customer' AS role,data->>'state' AS state FROM monosfer.delivery_projections WHERE stream=$1 AND updated_block<=$2
        UNION ALL
        SELECT data->>'courier','courier',data->>'state' FROM monosfer.delivery_projections WHERE stream=$1 AND updated_block<=$2
      ) SELECT wallet,jsonb_build_object(
        'customerDeliveries',count(*) FILTER(WHERE role='customer')::text,
        'courierDeliveries',count(*) FILTER(WHERE role='courier')::text,
        'customerCompleted',count(*) FILTER(WHERE role='customer' AND state='Completed')::text,
        'courierCompleted',count(*) FILTER(WHERE role='courier' AND state='Completed')::text,
        'returned',count(*) FILTER(WHERE state='Returned')::text,
        'cancelled',count(*) FILTER(WHERE state='Cancelled')::text,
        'expired',count(*) FILTER(WHERE state='Expired')::text) AS counters
      FROM observations WHERE wallet ~ '^0x[0-9a-f]{40}$' AND wallet<>'0x0000000000000000000000000000000000000000'
      AND state IN ('Bidding','AwaitingFunding','ReadyForPickup','InTransit','DeliveredPending','ReturnRequired','Disputed','Completed','Returned','Resolved','Cancelled','Expired')
      GROUP BY wallet ORDER BY wallet`,[cursor.stream,cursor.last_block])).rows;
      if(apply) {
        // Replace only derived rows for this trusted stream, preserving audit and source events.
        await client.query('DELETE FROM monosfer.referral_reward_projections WHERE stream=$1',[cursor.stream]);
        await client.query('DELETE FROM monosfer.reputation_projections WHERE stream=$1',[cursor.stream]);
        for(const row of rows) {
          await client.query(`INSERT INTO monosfer.reputation_projections(stream,wallet,counters,source_block,source_hash,export_fingerprint) VALUES($1,$2,$3,$4,$5,$6)`,
            [cursor.stream,row.wallet,row.counters,cursor.last_block,cursor.last_hash,cursor.export_fingerprint]);
          await client.query(`INSERT INTO monosfer.referral_reward_projections(stream,wallet,status,source_block,source_hash,export_fingerprint) VALUES($1,$2,'pending_policy',$3,$4,$5)`,
            [cursor.stream,row.wallet,cursor.last_block,cursor.last_hash,cursor.export_fingerprint]);
        }
        await client.query(`INSERT INTO monosfer.ops_drill_runs(id,kind,stream,status,duration_ms,result) VALUES($1,'projection_rebuild',$2,'passed',$3,$4)`,
          [randomUUID(),cursor.stream,Date.now()-start,{walletCount:rows.length,sourceBlock:cursor.last_block}]);
      }
      return {mode:apply?'apply':'dry-run',walletCount:rows.length,sourceBlock:cursor.last_block,status:'passed'};
    });
  }
}
