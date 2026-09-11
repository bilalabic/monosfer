import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { createHash, randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { link, lstat, mkdir, readFile, unlink, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

export const checksum=(text:string|Uint8Array)=>createHash('sha256').update(text).digest('hex');
export async function bounded<T>(milliseconds:number,work:(signal:AbortSignal)=>Promise<T>):Promise<T>{
  const controller=new AbortController();let timer:ReturnType<typeof setTimeout>|undefined;
  try{return await Promise.race([work(controller.signal),new Promise<never>((_,reject)=>{timer=setTimeout(()=>{controller.abort();reject(new ServiceUnavailableException());},milliseconds);})]);}
  catch{throw new ServiceUnavailableException();}finally{clearTimeout(timer);controller.abort();}
}
export interface Point {lat:number;lng:number}
export interface RouteEstimate {provider:string;distanceMeters:number;durationSeconds:number;estimatedAt:string}
export abstract class RouteProvider {abstract estimate(pickup:Point,dropoff:Point,signal:AbortSignal):Promise<RouteEstimate>}
@Injectable()
export class DevelopmentRouteProvider extends RouteProvider {
  async estimate(a:Point,b:Point,signal:AbortSignal):Promise<RouteEstimate>{
    signal.throwIfAborted();
    const radians=(n:number)=>n*Math.PI/180;
    const h=Math.sin(radians(b.lat-a.lat)/2)**2+Math.cos(radians(a.lat))*Math.cos(radians(b.lat))*Math.sin(radians(b.lng-a.lng)/2)**2;
    const distanceMeters=Math.round(6371000*2*Math.asin(Math.sqrt(Math.min(1,h))));
    return {provider:'straight-line-dev',distanceMeters,durationSeconds:Math.ceil(distanceMeters/5),estimatedAt:new Date().toISOString()};
  }
}
export abstract class EvidenceStorage {
  abstract put(key:string,ciphertext:string,signal:AbortSignal):Promise<void>;
  abstract get(key:string,signal:AbortSignal):Promise<string>;
}
@Injectable()
export class LocalEvidenceStorage extends EvidenceStorage {
  readonly root=fileURLToPath(new URL('../../.local/evidence/',import.meta.url));
  private async directory(){
    const parent=fileURLToPath(new URL('../../.local/',import.meta.url));
    for(const path of [parent,this.root]){
      try{await mkdir(path,{mode:0o700});}catch(error){if((error as NodeJS.ErrnoException).code!=='EEXIST')throw error;}
      const info=await lstat(path);if(!info.isDirectory()||info.isSymbolicLink())throw new Error('Invalid local storage');
    }
  }
  private path(key:string){if(!/^[0-9a-f-]{36}$/.test(key))throw new Error('Invalid object key');return join(this.root,`${key}.json`);}
  async put(key:string,text:string,signal:AbortSignal){
    await this.directory();const path=this.path(key);const temporary=join(this.root,`${randomUUID()}.tmp`);
    try{
      await writeFile(temporary,text,{flag:'wx',mode:0o600,signal});signal.throwIfAborted();
      try{await link(temporary,path);}catch(error){
        if((error as NodeJS.ErrnoException).code!=='EEXIST'||await this.get(key,signal)!==text)throw new Error('Object integrity mismatch');
      }
    }finally{try{await unlink(temporary);}catch(error){if((error as NodeJS.ErrnoException).code!=='ENOENT')throw error;}}
  }
  async get(key:string,signal:AbortSignal){
    await this.directory();const path=this.path(key);const info=await lstat(path);
    if(!info.isFile()||info.isSymbolicLink()||info.size>131072)throw new Error('Invalid object');
    return readFile(path,{encoding:'utf8',signal});
  }
}
export interface NotificationInput {wallet:string;stream:string;deliveryId:string;binding:string;template:'delivery_state'|'evidence_ready';arguments:Record<string,string>}
export abstract class NotificationProvider {abstract send(idempotencyKey:string,input:NotificationInput,signal:AbortSignal):Promise<void>}
@Injectable()
export class InAppNotificationProvider extends NotificationProvider {
  // Durable delivery is the worker's SQL inbox insert. No third-party network sends.
  async send(_key:string,_input:NotificationInput,signal:AbortSignal):Promise<void>{signal.throwIfAborted();}
}
