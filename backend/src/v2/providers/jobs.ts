import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import type { PoolClient } from 'pg';
import { ConfigService } from '../config/config.js';
import { PrivateDataCrypto } from '../private-data/crypto.js';
import { checksum, type NotificationInput } from './adapters.js';

@Injectable()
export class ProviderJobs {
  readonly crypto:PrivateDataCrypto;
  constructor(private readonly config:ConfigService){this.crypto=new PrivateDataCrypto(config.settings);}
  available(){if(!this.config.settings.operations.enabled||this.config.settings.environment==='production')throw new ServiceUnavailableException();}
  async enqueue(client:PoolClient,kind:'evidence.store'|'notification.send',dedup:string,payload:Record<string,unknown>,evidenceId?:string){
    const id=randomUUID();const envelope=this.crypto.encrypt(payload,`monosfer/provider-job/v1/${id}`);
    await client.query(`INSERT INTO monosfer.provider_jobs(id,kind,dedup_key,encrypted_payload,evidence_id,stream) VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(dedup_key) DO NOTHING`,
      [id,kind,dedup,JSON.stringify(envelope),evidenceId??null,String(payload.stream)]);
  }
  async notify(client:PoolClient,input:NotificationInput){
    const dedup=checksum(JSON.stringify([input.wallet,input.binding,input.template,input.arguments]));
    return this.enqueue(client,'notification.send',dedup,input as unknown as Record<string,unknown>);
  }
}
