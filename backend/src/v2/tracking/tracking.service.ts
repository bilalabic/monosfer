import { BadRequestException, ForbiddenException, Injectable } from '@nestjs/common';
import { ConfigService } from '../config/config.js';
import { DeliveryAccess, type DeliveryContext } from '../operations/access.js';
import { PrivateDataCrypto } from '../private-data/crypto.js';
import { token } from '../security/tokens.js';
import { privateHash } from '../quotes/idempotency.js';
import type { AuthContext } from '../auth/auth.service.js';
import { TrackingStore } from './store.js';
import type { TrackingLocationDto } from './tracking.dto.js';

@Injectable()
export class TrackingService {
  readonly crypto:PrivateDataCrypto;
  constructor(private readonly config:ConfigService,private readonly access:DeliveryAccess,private readonly store:TrackingStore){this.crypto=new PrivateDataCrypto(config.settings);}
  private value(context:DeliveryContext,auth:AuthContext){return JSON.stringify({auth:auth.sessionHash,wallet:auth.user.walletAddress.toLowerCase(),binding:context.binding});}
  private raw(value:unknown):string{if(typeof value!=='string'||! /^[a-f0-9]{64}$/.test(value))throw new ForbiddenException();return value;}
  async create(id:string,auth:AuthContext){
    return this.access.withDelivery(id,auth.user.walletAddress,true,async context=>{
      const ttl=Math.min(this.config.settings.operations.sessionTtl,Math.floor((Date.parse(auth.session.expiresAt)-Date.now())/1000));
      if(ttl<1)throw new ForbiddenException();const raw=token();
      await this.store.create(context.binding,auth.sessionHash,raw,this.value(context,auth),ttl);
      return {trackingSession:raw,expiresAt:new Date(Date.now()+ttl*1000).toISOString(),mode:auth.user.walletAddress.toLowerCase()===context.courier?'publish':'view'};
    });
  }
  async revoke(id:string,auth:AuthContext,raw:unknown){return this.access.withDelivery(id,auth.user.walletAddress,true,
    context=>this.store.revoke(context.binding,auth.sessionHash,this.raw(raw),this.value(context,auth)));}
  async publish(id:string,auth:AuthContext,raw:unknown,input:TrackingLocationDto){
    const captured=Date.parse(input.capturedAt);const now=Date.now();const s=this.config.settings.operations;
    if(!Number.isFinite(captured)||captured>now+5000||captured<now-s.locationTtl*1000)throw new BadRequestException();
    return this.access.withDelivery(id,auth.user.walletAddress,true,async context=>{
      if(auth.user.walletAddress.toLowerCase()!==context.courier)throw new ForbiddenException();
      const data={...input,receivedAt:new Date(now).toISOString(),expiresAt:new Date(now+s.locationTtl*1000).toISOString()};
      const encrypted=this.crypto.encrypt(data,`monosfer/tracking/v1/${context.binding}`);
      const eventId=await this.store.publish(context.binding,auth.sessionHash,this.raw(raw),this.value(context,auth),input.sequence,
        privateHash(input,this.config.settings.privateDataMasterKeyB64),captured,JSON.stringify(encrypted),s.locationTtl,s.eventTtl);
      return {eventId};
    });
  }
  async read(id:string,auth:AuthContext,raw:unknown,after?:string){
    if(after!==undefined&&!/^\d{1,16}-\d{1,16}$/.test(after))throw new BadRequestException();
    return this.access.withDelivery(id,auth.user.walletAddress,true,async context=>{
      const batch=await this.store.read(context.binding,auth.sessionHash,this.raw(raw),this.value(context,auth),after);
      const decode=(entry:{id:string;payload:string})=>{
        const data=this.crypto.decrypt(JSON.parse(entry.payload),`monosfer/tracking/v1/${context.binding}`);
        return Date.parse(String(data.expiresAt))>Date.now()?{eventId:entry.id,location:data}:null;
      };
      const latest=batch.latest?decode(batch.latest):null;
      return {reset:batch.reset,latest,events:batch.events.map(decode).filter(e=>e!==null),cursor:batch.events.at(-1)?.id??after??'0-0'};
    });
  }
}
