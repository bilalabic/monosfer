import { ConflictException, ForbiddenException, Injectable } from '@nestjs/common';
import { RedisService } from '../infrastructure/redis.module.js';
import { hash } from '../security/tokens.js';

const authenticate=`if redis.call('GET',KEYS[1])~=ARGV[1] or redis.call('GET',KEYS[2])~=ARGV[2] then return {'denied'} end `;
@Injectable()
export class TrackingStore {
  constructor(private readonly redis:RedisService){}
  keys(scope:string,authHash:string,raw:string){const base=`tracking:{${scope}}`;return {base,session:`${base}:session:${hash(raw)}`,slot:`${base}:slot:${authHash}`};}
  async create(scope:string,authHash:string,raw:string,value:string,ttl:number){
    const k=this.keys(scope,authHash,raw);
    await this.redis.command(c=>c.eval("redis.call('SET',KEYS[1],ARGV[1],'EX',ARGV[3]);redis.call('SET',KEYS[2],ARGV[2],'EX',ARGV[3]);return 1",
      {keys:[k.session,k.slot],arguments:[value,hash(raw),String(ttl)]}));
  }
  async check(scope:string,authHash:string,raw:string,value:string){
    const k=this.keys(scope,authHash,raw);
    const result=await this.redis.command(c=>c.eval(authenticate+"return {'ok'}",{keys:[k.session,k.slot],arguments:[value,hash(raw)]}));
    if((result as string[])[0]!=='ok')throw new ForbiddenException();
  }
  async revoke(scope:string,authHash:string,raw:string,value:string){
    const k=this.keys(scope,authHash,raw);
    const result=await this.redis.command(c=>c.eval(authenticate+"redis.call('DEL',KEYS[1],KEYS[2],KEYS[3]);return {'ok'}",
      {keys:[k.session,k.slot,`${k.session}:seq`],arguments:[value,hash(raw)]}));
    if((result as string[])[0]!=='ok')throw new ForbiddenException();
  }
  async publish(scope:string,authHash:string,raw:string,value:string,sequence:number,payloadHash:string,captured:number,envelope:string,locationTtl:number,eventTtl:number){
    const k=this.keys(scope,authHash,raw);
    const script=authenticate+`
      local seq=tonumber(redis.call('HGET',KEYS[3],'seq') or '0')
      if tonumber(ARGV[3])==seq and redis.call('HGET',KEYS[3],'hash')==ARGV[4] then return {'ok',redis.call('HGET',KEYS[3],'id')} end
      if tonumber(ARGV[3])<=seq or tonumber(ARGV[5])<=tonumber(redis.call('GET',KEYS[6]) or '0') then return {'conflict'} end
      local id=redis.call('XADD',KEYS[4],'MAXLEN','=','128','*','payload',ARGV[6])
      redis.call('EXPIRE',KEYS[4],ARGV[8])
      redis.call('SET',KEYS[5],cjson.encode({id=id,payload=ARGV[6]}),'EX',ARGV[7])
      redis.call('SET',KEYS[6],ARGV[5],'EX',ARGV[8])
      redis.call('HSET',KEYS[3],'seq',ARGV[3],'hash',ARGV[4],'id',id)
      redis.call('EXPIRE',KEYS[3],redis.call('TTL',KEYS[1]))
      return {'ok',id}`;
    const result=await this.redis.command(c=>c.eval(script,{keys:[k.session,k.slot,`${k.session}:seq`,`${k.base}:events`,`${k.base}:latest`,`${k.base}:captured`],
      arguments:[value,hash(raw),String(sequence),payloadHash,String(captured),envelope,String(locationTtl),String(eventTtl)]})) as string[];
    if(result[0]==='denied')throw new ForbiddenException();if(result[0]!=='ok')throw new ConflictException();return result[1]!;
  }
  async read(scope:string,authHash:string,raw:string,value:string,after?:string){
    const k=this.keys(scope,authHash,raw);
    const result=await this.redis.command(c=>c.eval(authenticate+`
      return {'ok',redis.call('GET',KEYS[3]) or '',redis.call('XRANGE',KEYS[4],'-','+','COUNT',1),
        redis.call('XRANGE',KEYS[4],'('..ARGV[3],'+','COUNT',32),redis.call('XREVRANGE',KEYS[4],'+','-','COUNT',1)}`,
    {keys:[k.session,k.slot,`${k.base}:latest`,`${k.base}:events`],arguments:[value,hash(raw),after??'0-0']})) as [string,string,[string,string[]][],[string,string[]][],[string,string[]][]];
    if(result[0]!=='ok')throw new ForbiddenException();
    const latest=result[1]?JSON.parse(result[1]) as {id:string;payload:string}:null;
    const first=result[2][0]?.[0];
    const less=(a:string,b:string)=>{const [am,as]=a.split('-').map(BigInt);const [bm,bs]=b.split('-').map(BigInt);return am!<bm!||(am===bm&&as!<bs!);};
    const last=result[4][0]?.[0];
    const reset=!after||Boolean(first&&less(after,first))||Boolean(after&&!first)||Boolean(after&&last&&less(last,after));
    return {reset,latest,events:reset?(latest?[latest]:[]):result[3].map(([id,fields])=>({id,payload:fields[1]!}))};
  }
}
