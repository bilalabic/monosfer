import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { ConfigService } from '../config/config.js';
import { DeliveryAccess } from '../operations/access.js';
import { RedisService } from '../infrastructure/redis.module.js';
import { PrivateDataCrypto } from '../private-data/crypto.js';
import { PrivateDataService } from '../private-data/private-data.module.js';
import { idempotencyScope, privateHash } from '../quotes/idempotency.js';
import { bounded, checksum, EvidenceStorage, RouteProvider, type Point } from './adapters.js';
import { ProviderJobs } from './jobs.js';
import type { EvidenceInputDto } from './providers.dto.js';

@Injectable()
export class RouteService {
  private readonly crypto:PrivateDataCrypto;
  constructor(private readonly config:ConfigService,private readonly access:DeliveryAccess,private readonly data:PrivateDataService,
    private readonly redis:RedisService,private readonly provider:RouteProvider){this.crypto=new PrivateDataCrypto(config.settings);}
  async route(id:string,wallet:string){
    return this.access.withDelivery(id,wallet,true,async context=>{
      const key=`route:${context.binding}`;const aad=`monosfer/route/v1/${context.binding}`;const stored=await this.redis.get(key);
      if(stored){const cached=this.crypto.decrypt(JSON.parse(stored),aad);if(Date.parse(String(cached.expiresAt))>Date.now())return cached;}
      const payload=await this.data.readDelivery(context.privateRecordId,wallet);
      const point=(value:unknown):Point=>{const p=value as Point;if(!p||!Number.isFinite(p.lat)||Math.abs(p.lat)>90||!Number.isFinite(p.lng)||Math.abs(p.lng)>180)throw new ServiceUnavailableException();return {lat:p.lat,lng:p.lng};};
      const estimate=await bounded(this.config.settings.operations.providerTimeoutMs,signal=>this.provider.estimate(point(payload.pickup),point(payload.dropoff),signal));
      if(!Number.isSafeInteger(estimate.distanceMeters)||estimate.distanceMeters<0||!Number.isSafeInteger(estimate.durationSeconds)||estimate.durationSeconds<0||
        !Number.isFinite(Date.parse(estimate.estimatedAt))||Math.abs(Date.now()-Date.parse(estimate.estimatedAt))>this.config.settings.operations.routeTtl*1000)throw new ServiceUnavailableException();
      const result={provider:estimate.provider,distanceMeters:estimate.distanceMeters,durationSeconds:estimate.durationSeconds,estimatedAt:estimate.estimatedAt,
        expiresAt:new Date(Date.now()+this.config.settings.operations.routeTtl*1000).toISOString()};
      await this.redis.set(key,JSON.stringify(this.crypto.encrypt(result,aad)),this.config.settings.operations.routeTtl);return result;
    });
  }
}
@Injectable()
export class EvidenceService {
  constructor(private readonly config:ConfigService,private readonly access:DeliveryAccess,private readonly jobs:ProviderJobs,private readonly storage:EvidenceStorage){}
  private validate(input:EvidenceInputDto){
    if(input.contentType==='text/plain'){
      if(!input.text?.trim()||input.contentBase64!==undefined||Buffer.byteLength(input.text)>8192)throw new BadRequestException();
      return Buffer.from(input.text);
    }
    if(input.text!==undefined||!input.contentBase64)throw new BadRequestException();
    const bytes=Buffer.from(input.contentBase64,'base64');
    if(bytes.toString('base64')!==input.contentBase64||bytes.length>24576||
      (input.contentType==='image/png'?!bytes.subarray(0,8).equals(Buffer.from('89504e470d0a1a0a','hex')):
        input.contentType==='image/jpeg'?!(bytes[0]===255&&bytes[1]===216&&bytes[2]===255):true))throw new BadRequestException();
    return bytes;
  }
  async create(id:string,wallet:string,key:unknown,input:EvidenceInputDto){
    const bytes=this.validate(input);wallet=wallet.toLowerCase();
    return this.access.withDelivery(id,wallet,true,async(context,client)=>{
      const scope=idempotencyScope(key,wallet,'evidence',context.binding,this.config.settings.privateDataMasterKeyB64);
      const requestHash=privateHash(input,this.config.settings.privateDataMasterKeyB64);
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[scope]);
      const previous=(await client.query('SELECT * FROM monosfer.evidence_packages WHERE scope_hash=$1',[scope])).rows[0];
      if(previous){if(previous.request_hash!==requestHash)throw new ConflictException();return {evidenceId:previous.id,status:previous.status,contentType:previous.content_type};}
      const evidenceId=randomUUID();const payload={...input,evidenceHash:checksum(bytes)};
      const envelope=this.jobs.crypto.encrypt(payload,`monosfer/evidence/v1/${evidenceId}/${context.binding}`);
      const ciphertext=JSON.stringify(envelope);
      await client.query(`INSERT INTO monosfer.evidence_packages(id,scope_hash,request_hash,stream,delivery_id,private_record_id,binding,submitter,content_type,ciphertext_hash)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,[evidenceId,scope,requestHash,context.stream,id,context.privateRecordId,context.binding,wallet,input.contentType,checksum(ciphertext)]);
      await this.jobs.enqueue(client,'evidence.store',scope,{evidenceId,deliveryId:id,stream:context.stream,wallet,binding:context.binding,ciphertext},evidenceId);
      return {evidenceId,status:'pending',contentType:input.contentType};
    });
  }
  async read(id:string,wallet:string,evidenceId:string,content=false){
    return this.access.withDelivery(id,wallet,false,async(context,client)=>{
      const row=(await client.query('SELECT * FROM monosfer.evidence_packages WHERE id=$1 AND stream=$2 AND delivery_id=$3',[evidenceId,context.stream,id])).rows[0];
      if(!row)throw new NotFoundException();
      if(row.submitter!==wallet.toLowerCase()||row.binding!==context.binding)throw new ForbiddenException();
      if(!content)return {evidenceId,status:row.status,contentType:row.content_type};
      if(row.status!=='ready')throw new ConflictException();
      const ciphertext=await bounded(this.config.settings.operations.providerTimeoutMs,signal=>this.storage.get(evidenceId,signal));
      if(checksum(ciphertext)!==row.ciphertext_hash)throw new ServiceUnavailableException();
      const data=this.jobs.crypto.decrypt(JSON.parse(ciphertext),`monosfer/evidence/v1/${evidenceId}/${context.binding}`);
      if(checksum(this.validate(data as unknown as EvidenceInputDto))!==data.evidenceHash)throw new ServiceUnavailableException();
      return data;
    });
  }
}
