import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '../config/config.js';
import { QuotesRepository, type Issuance } from './quotes.repository.js';
import { supportsQuoteNetwork } from './config.js';

@Injectable()
export class QuoteLinkWorker {
  constructor(private readonly config: ConfigService, private readonly repository: QuotesRepository) {}
  async once(): Promise<{ processed: number; linked: number }> {
    const s=this.config.settings;
    if (!supportsQuoteNetwork(s.environment,s.indexer.chainId,s.indexer.rpcUrl) || !s.quotes.workerEnabled || !s.indexer.enabled) throw new ServiceUnavailableException();
    let processed=0; let linked=0;
    for (let n=0;n<20;n++) {
      const result=await this.repository.transaction(async client=>{
        const item=(await client.query<Issuance & { outbox_id:string; attempts:number }>(`SELECT q.*,o.id AS outbox_id,o.attempts
          FROM monosfer.transactional_outbox o JOIN monosfer.risk_quote_issuances q ON q.digest=o.quote_digest
          WHERE o.topic='quote.link' AND o.status='pending' AND o.next_attempt_at<=now() AND q.stream=$1
          ORDER BY o.next_attempt_at,o.created_at LIMIT 1 FOR UPDATE OF o SKIP LOCKED`,
          [`${s.indexer.chainId}:${s.indexer.deployment!.address.toLowerCase()}`])).rows[0];
        if (!item) return null;
        const record=(await client.query(`SELECT id FROM monosfer.private_delivery_records WHERE id=$1
          AND source='quote_api' AND customer_wallet=$2 FOR UPDATE`,[item.private_record_id,item.customer])).rows[0];
        const delivery=record?await this.repository.trustedDelivery(client,item):null;
        if (delivery) {
          await client.query(`INSERT INTO monosfer.private_delivery_links(private_record_id,stream,delivery_id,quote_digest)
            VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING`,[item.private_record_id,item.stream,delivery.delivery_id,item.digest]);
          const bound=await client.query(`SELECT 1 FROM monosfer.private_delivery_links WHERE private_record_id=$1
            AND stream=$2 AND delivery_id=$3 AND quote_digest=$4`,[item.private_record_id,item.stream,delivery.delivery_id,item.digest]);
          if (bound.rowCount) {
            await client.query(`UPDATE monosfer.transactional_outbox SET status='completed',completed_at=now(),attempts=attempts+1 WHERE id=$1`,[item.outbox_id]);
            return true;
          }
        }
        // Pending can outlive expiry: a delayed finalized event still establishes ownership.
        const delay=Math.min(2**Math.min(item.attempts,6),60);
        await client.query(`UPDATE monosfer.transactional_outbox SET attempts=attempts+1,
          next_attempt_at=now()+($2::integer * interval '1 second') WHERE id=$1`,[item.outbox_id,delay]);
        return false;
      });
      if (result===null) break;
      processed++; if(result) linked++;
    }
    return {processed,linked};
  }
}
