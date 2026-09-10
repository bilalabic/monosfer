import { ForbiddenException, HttpException, Injectable, ServiceUnavailableException } from '@nestjs/common';
import { DatabaseService } from '../infrastructure/database.module.js';
import { ConfigService } from '../config/config.js';
import { DeliveryAccess } from '../operations/access.js';
import { ProviderJobs } from './jobs.js';
import { bounded, EvidenceStorage, NotificationProvider, type NotificationInput } from './adapters.js';

@Injectable()
export class ProviderWorker {
  constructor(private readonly db:DatabaseService,private readonly config:ConfigService,private readonly access:DeliveryAccess,
    private readonly jobs:ProviderJobs,private readonly storage:EvidenceStorage,private readonly notifications:NotificationProvider){}
  private async lifecycle(){
    const s=this.config.settings.indexer;const stream=`${s.chainId}:${s.deployment!.address.toLowerCase()}`;
    const candidates=await this.db.query(`SELECT d.delivery_id::text AS id,d.data->>'customer' AS customer FROM monosfer.delivery_projections d
      JOIN monosfer.private_delivery_links l ON l.stream=d.stream AND l.delivery_id=d.delivery_id
      LEFT JOIN monosfer.notification_cursors c ON c.stream=d.stream AND c.delivery_id=d.delivery_id
      WHERE d.stream=$1 AND (c.state IS DISTINCT FROM d.data->>'state' OR c.courier IS DISTINCT FROM d.data->>'courier' OR c.quote_digest IS DISTINCT FROM d.data->>'quoteDigest')
      ORDER BY d.delivery_id LIMIT 20`,[stream]);
    for(const row of candidates.rows){
      try{await this.access.withDelivery(row.id,row.customer,false,async(context,client)=>{
        for(const wallet of new Set([context.customer,context.courier])){
          if(!/^0x[0-9a-f]{40}$/.test(wallet)||/^0x0{40}$/.test(wallet))continue;
          await this.jobs.notify(client,{wallet,stream:context.stream,deliveryId:context.id,binding:context.binding,
            template:'delivery_state',arguments:{state:context.state}});
        }
        await client.query(`INSERT INTO monosfer.notification_cursors(stream,delivery_id,state,courier,quote_digest)
          SELECT $1,$2,$3,$4,data->>'quoteDigest' FROM monosfer.delivery_projections WHERE stream=$1 AND delivery_id=$2
          ON CONFLICT(stream,delivery_id) DO UPDATE SET state=excluded.state,courier=excluded.courier,quote_digest=excluded.quote_digest`,
        [context.stream,context.id,context.state,context.courier]);
      });}catch(error){if(!(error instanceof ForbiddenException))throw error;}
    }
  }
  async once(){
    this.access.available();if(!this.config.settings.operations.workerEnabled)throw new ServiceUnavailableException();
    let completed=0;let failed=0;
    try{
      await this.lifecycle();
      for(let n=0;n<20;n++){
        const result=await this.db.transaction(async client=>{
          const s=this.config.settings.indexer;
          const row=(await client.query(`SELECT * FROM monosfer.provider_jobs WHERE status='pending' AND next_attempt_at<=now() AND stream=$1
            ORDER BY next_attempt_at,created_at LIMIT 1 FOR UPDATE SKIP LOCKED`,[`${s.chainId}:${s.deployment!.address.toLowerCase()}`])).rows[0];
          if(!row)return null;await client.query('SAVEPOINT execute_provider');
          try{
            const payload=this.jobs.crypto.decrypt(row.encrypted_payload,`monosfer/provider-job/v1/${row.id}`);
            await this.access.withDelivery(String(payload.deliveryId),String(payload.wallet),false,async context=>{
              if(context.binding!==payload.binding)throw new ForbiddenException();
              if(row.kind==='evidence.store'){
                await bounded(this.config.settings.operations.providerTimeoutMs,signal=>this.storage.put(String(payload.evidenceId),String(payload.ciphertext),signal));
                await client.query("UPDATE monosfer.evidence_packages SET status='ready' WHERE id=$1",[row.evidence_id]);
                await this.jobs.notify(client,{wallet:String(payload.wallet),stream:context.stream,deliveryId:context.id,binding:context.binding,
                  template:'evidence_ready',arguments:{evidenceId:String(payload.evidenceId)}});
              }else{
                const notification=payload as unknown as NotificationInput;
                // An obsolete lifecycle notification is completed without sending stale status.
                if(notification.template==='delivery_state'&&notification.arguments.state!==context.state)return;
                await bounded(this.config.settings.operations.providerTimeoutMs,signal=>this.notifications.send(row.id,notification,signal));
                await client.query(`INSERT INTO monosfer.notifications(id,wallet,stream,delivery_id,binding,template,arguments)
                  VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(id) DO NOTHING`,
                  [row.id,notification.wallet,context.stream,context.id,context.binding,notification.template,JSON.stringify(notification.arguments)]);
              }
            });
            await client.query("UPDATE monosfer.provider_jobs SET status='done',attempts=attempts+1,completed_at=now(),last_error=NULL WHERE id=$1",[row.id]);
            return true;
          }catch{
            await client.query('ROLLBACK TO SAVEPOINT execute_provider');
            const terminal=row.attempts+1>=this.config.settings.operations.maxAttempts;
            await client.query(`UPDATE monosfer.provider_jobs SET status=$2,attempts=attempts+1,last_error='PROVIDER_UNAVAILABLE',
              next_attempt_at=now()+($3::integer*interval '1 second') WHERE id=$1`,[row.id,terminal?'failed':'pending',Math.min(2**row.attempts,60)]);
            if(terminal&&row.evidence_id)await client.query("UPDATE monosfer.evidence_packages SET status='failed' WHERE id=$1",[row.evidence_id]);
            return false;
          }
        });
        if(result===null)break;if(result)completed++;else failed++;
      }
      return {completed,failed};
    }catch(error){if(error instanceof HttpException)throw error;throw new ServiceUnavailableException();}
  }
}
