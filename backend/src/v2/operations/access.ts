import { createHash } from 'node:crypto';
import { ForbiddenException, HttpException, Injectable, Module, ServiceUnavailableException } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { ConfigService } from '../config/config.js';
import { DatabaseModule, DatabaseService } from '../infrastructure/database.module.js';

export interface DeliveryContext {
  id:string; stream:string; privateRecordId:string; customer:string; courier:string; state:string; binding:string;
}
export const activeStates=['ReadyForPickup','InTransit'];
const knownStates=[...activeStates,'Bidding','AwaitingFunding','DeliveredPending','ReturnRequired','Completed','Returned','Cancelled','Expired'];
@Injectable()
export class DeliveryAccess {
  constructor(private readonly db:DatabaseService,private readonly config:ConfigService){}
  available() {
    const s=this.config.settings;
    if(!s.operations.enabled||s.environment==='production'||!s.indexer.enabled)throw new ServiceUnavailableException();
  }
  async withDelivery<T>(id:string,wallet:string,active:boolean,work:(context:DeliveryContext,client:PoolClient)=>Promise<T>):Promise<T>{
    this.available();const s=this.config.settings.indexer;
    if(!/^(0|[1-9][0-9]{0,77})$/.test(id)||BigInt(id)>=2n**256n)throw new ForbiddenException();
    try{return await this.db.transaction(async client=>{
      const row=(await client.query(`SELECT d.data,l.private_record_id FROM monosfer.delivery_projections d
        JOIN monosfer.indexer_streams s ON s.stream=d.stream
        JOIN monosfer.private_delivery_links l ON l.stream=d.stream AND l.delivery_id=d.delivery_id AND l.quote_digest=d.data->>'quoteDigest'
        JOIN monosfer.private_delivery_records p ON p.id=l.private_record_id AND p.customer_wallet=d.data->>'customer'
        WHERE d.stream=$1 AND d.delivery_id=$2 AND s.status='ready' AND s.integrity_ok AND s.last_block=s.observed_head
        AND s.export_fingerprint=$3 AND s.checked_at>now()-($4::integer*interval '1 second')
        FOR SHARE OF s,d,l,p`,[`${s.chainId}:${s.deployment!.address.toLowerCase()}`,id,s.fingerprint,s.staleSeconds])).rows[0];
      if(!row||!knownStates.includes(row.data.state)||(active&&!activeStates.includes(row.data.state)))throw new ForbiddenException();
      const customer=String(row.data.customer).toLowerCase();const courier=String(row.data.courier).toLowerCase();
      if(![customer,courier].includes(wallet.toLowerCase()))throw new ForbiddenException();
      const stream=`${s.chainId}:${s.deployment!.address.toLowerCase()}`;
      const binding=createHash('sha256').update(JSON.stringify([stream,id,row.private_record_id,row.data.quoteDigest,customer,courier,s.fingerprint])).digest('hex');
      return work({id,stream,privateRecordId:row.private_record_id,customer,courier,state:row.data.state,binding},client);
    });}catch(error){if(error instanceof HttpException)throw error;throw new ServiceUnavailableException();}
  }
}
@Module({imports:[DatabaseModule],providers:[DeliveryAccess],exports:[DeliveryAccess]})
export class DeliveryAccessModule {}
