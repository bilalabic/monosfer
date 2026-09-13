import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { ConflictException, ForbiddenException, HttpException, Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '../config/config.js';
import { DatabaseService } from '../infrastructure/database.module.js';
import { RedisService } from '../infrastructure/redis.module.js';
import { PrivateDataCrypto, recordAad } from '../private-data/crypto.js';
import { trustedDelivery } from '../support/trusted.js';
import { idempotencyScope, privateHash } from '../quotes/idempotency.js';
import { ProofChain } from './chain.js';
import type { ProofKind } from './typed-data.js';
import type { PodInputDto, AcceptanceInputDto } from './proofs.dto.js';
export function verifyDeliveryCode(expected:unknown,provided:string) {
  if(typeof expected!=='string'||!expected.length||!timingSafeEqual(createHash('sha256').update(expected).digest(),createHash('sha256').update(provided).digest()))throw new ForbiddenException();
}
@Injectable()
export class ProofsService {
  private readonly crypto:PrivateDataCrypto;
  constructor(private readonly db:DatabaseService,private readonly config:ConfigService,private readonly chain:ProofChain,private readonly redis:RedisService){this.crypto=new PrivateDataCrypto(config.settings);}
  async issue(kind:ProofKind,id:string,wallet:string,key:unknown,input:PodInputDto|AcceptanceInputDto) {
    const s=this.config.settings; wallet=wallet.toLowerCase();
    const scope=idempotencyScope(key,wallet,`proof:${kind}:${id}`,`${s.indexer.chainId}:${s.indexer.deployment?.address}`,s.privateDataMasterKeyB64);
    const requestHash=privateHash(input,s.privateDataMasterKeyB64); const aad=`monosfer/proof-response/v1/${scope}`;
    try{return await this.db.transaction(async client=>{
      const {cursor,data,record}=await trustedDelivery(client,s,id,kind==='pod');
      if(wallet!==(kind==='pod'?data.courier:data.customer))throw new ForbiddenException();
      if(data.state!==({pickup:'ReadyForPickup',return:'ReturnRequired',pod:'InTransit'} as const)[kind])throw new ConflictException();
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[scope]);
      const cached=(await client.query('SELECT * FROM monosfer.proof_issuances WHERE scope_hash=$1',[scope])).rows[0];
      if(cached&&(cached.request_hash!==requestHash||cached.expires_at.getTime()<=Date.now()||cached.idempotency_expires_at.getTime()<=Date.now()))throw new ConflictException();
      const snapshot=await this.chain.snapshot(kind,id,data,cursor.last_block,cursor.last_hash);
      if(cached) {
        const response=this.crypto.decrypt(cached.encrypted_response,aad);
        const message=(kind==='pod'?response.attestation:response.acceptance) as Record<string,string>;
        if(kind==='pod'&&(message.proofType!==snapshot.proofType||Number(message.expiresAt)-Number(message.issuedAt)>snapshot.validity))throw new ConflictException();
        const checked=await this.chain.finish(kind,message,snapshot,data.customer!);
        if(checked.digest!==response.digest||(kind==='pod'&&checked.signature!==response.signature))throw new ConflictException();
        return response;
      }
      if(kind==='pod') {
        // Delivery-scoped budget also bounds distributed guesses; failures persist outside SQL rollback.
        const attempts=await this.redis.increment(`proof:attempts:${privateHash([cursor.stream,id],s.privateDataMasterKeyB64)}`,3600);
        if(attempts>5)throw new HttpException('Too Many Requests',429);
        const body=input as PodInputDto;
        if(body.proofType!=='otp')throw new ForbiddenException();
        const payload=this.crypto.decrypt(record!.encrypted_payload,recordAad(record!));
        verifyDeliveryCode((payload.dropoff as Record<string,unknown>|undefined)?.deliveryCode,body.code);
      }
      const nonce=BigInt(`0x${randomBytes(32).toString('hex')}`).toString();
      const issuedAt=BigInt(Math.floor(Date.now()/1000));
      const end=issuedAt+BigInt(snapshot.validity); const deadline=BigInt(data.stateDeadline!);
      const expiry=end<deadline?end:deadline;
      if(expiry<=issuedAt)throw new ConflictException();
      const message:Record<string,string>={deliveryId:id,courier:data.courier!,nonce,expiresAt:String(expiry)};
      if(kind==='pod')Object.assign(message,{proofType:snapshot.proofType,issuedAt:String(issuedAt),
        challengeHash:`0x${privateHash(['pod-challenge',cursor.stream,id,nonce,(input as PodInputDto).code],s.privateDataMasterKeyB64)}`});
      else message.action=snapshot.action!;
      const signed=await this.chain.finish(kind,message,snapshot,data.customer!);
      const expiresAt=new Date(Number(expiry)*1000).toISOString();
      const response={...(kind==='pod'?{attestation:message}:{acceptance:message}),...signed,expiresAt,status:'issued'};
      await client.query(`INSERT INTO monosfer.proof_issuances(scope_hash,request_hash,stream,delivery_id,actor,kind,encrypted_response,expires_at,idempotency_expires_at)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`,[scope,requestHash,cursor.stream,id,wallet,kind,this.crypto.encrypt(response,aad),expiresAt,new Date(Date.now()+s.proofs.idempotencyTtl*1000)]);
      return response;
    });}catch(error){if(error instanceof HttpException)throw error;throw new ServiceUnavailableException();}
  }
}
