import { randomUUID } from 'node:crypto';
import { unlink } from 'node:fs/promises';
import { join } from 'node:path';
import { runner } from 'node-pg-migrate';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { wallet, memoryStores, login, origin } from './auth.mjs';
import { testApplication, testEnv } from './app.mjs';
import { hubFixture, hashOf } from './indexer.mjs';
import { parseSettings, ConfigService } from '../../dist/config/config.js';
import { DatabaseService } from '../../dist/infrastructure/database.module.js';
import { RedisService } from '../../dist/infrastructure/redis.module.js';
import { PrivateDataCrypto, recordAad } from '../../dist/private-data/crypto.js';
import { DeliveryAccess } from '../../dist/operations/access.js';
import { LocalEvidenceStorage } from '../../dist/providers/adapters.js';
import { hash } from '../../dist/security/tokens.js';

export async function operationsFixture(t){
  const customer=wallet(),courier=wallet(),other=wallet();const hub=hubFixture(customer.address);
  const databaseUrl=process.env.DATABASE_URL??'postgresql://monosfer:local-development-only@127.0.0.1:55432/monosfer_v2';
  const redisUrl=process.env.REDIS_URL??'redis://:local-development-only@127.0.0.1:56379';
  for(const url of [databaseUrl,redisUrl])assert.ok(['localhost','127.0.0.1'].includes(new URL(url).hostname));
  assert.ok(['/monosfer_v2','/monosfer_v2_test'].includes(new URL(databaseUrl).pathname));
  const migration={databaseUrl,dir:fileURLToPath(new URL('../../migrations',import.meta.url)),direction:'up',migrationsTable:'pgmigrations',log:()=>{}};
  await runner(migration);assert.deepEqual(await runner(migration),[]);
  const settings={...parseSettings(testEnv),databaseUrl,redisUrl,connectionTimeoutMs:2000,indexer:hub.settings};
  settings.operations={...settings.operations,enabled:true,workerEnabled:true,pollMs:100,streamSeconds:5,locationTtl:2,sessionTtl:30,eventTtl:4,routeTtl:2};
  const config=new ConfigService(settings),db=new DatabaseService(config),redis=new RedisService(config);
  await redis.onModuleInit();assert.equal(await redis.ping(),true);
  const stores=memoryStores(),apps=[],bindings=[],tokens=[];
  const stream=`10143:${hub.address}`,recordIds=[randomUUID(),randomUUID()];
  const storage=new LocalEvidenceStorage();const crypto=new PrivateDataCrypto(settings);
  t.after(async()=>{
    try{
      await Promise.allSettled(apps.map(app=>app.close()));
      const evidence=(await db.query('SELECT id FROM monosfer.evidence_packages WHERE stream=$1',[stream])).rows;
      for(const row of evidence){assert.match(row.id,/^[0-9a-f-]{36}$/);try{await unlink(join(storage.root,`${row.id}.json`));}catch(e){if(e.code!=='ENOENT')throw e;}}
      for(const table of ['notifications','provider_jobs','evidence_packages','notification_cursors','private_delivery_links','bid_projections','delivery_projections','chain_event_inbox','indexer_blocks','indexer_streams']){
        await db.query(`DELETE FROM monosfer.${table} WHERE stream=$1`,[stream]);
      }
      await db.query('DELETE FROM monosfer.private_delivery_records WHERE id=ANY($1::uuid[])',[recordIds]);
      const keys=[];
      for(const binding of bindings){keys.push(...await redis.command(c=>c.keys(`tracking:{${binding}}:*`)));keys.push(`route:${binding}`);}
      keys.push(...tokens.map(raw=>`tracking:connection:${hash(raw)}`),...[...stores.sessions.keys()].map(id=>`auth:session:${id}`));
      if(await redis.ping())await redis.del(keys);
    }finally{redis.onApplicationShutdown();await db.onApplicationShutdown();}
  });
  await db.query(`INSERT INTO monosfer.indexer_streams(stream,chain_id,contract_address,export_fingerprint,start_block,last_block,last_hash,observed_head,status,checked_at)
    VALUES($1,10143,$2,$3,100,102,$4,102,'ready',now())`,[stream,hub.address,hub.settings.fingerprint,hashOf('ops-block')]);
  for(let id=0;id<2;id++){
    const context={id:recordIds[id],source_namespace:'quote-api-v1',source_collection:'deliveries',legacy_mongo_id:null,kind:'delivery',schema_version:1};
    const payload={pickup:{address:'OPS_PRIVATE_PICKUP',lat:41,lng:29,contactPhone:'OPS_PRIVATE_PHONE'},dropoff:{address:'OPS_PRIVATE_DROPOFF',lat:40,lng:28,deliveryCode:'OPS_PRIVATE_CODE'}};
    await db.query(`INSERT INTO monosfer.private_delivery_records(id,source,verification_status,source_namespace,source_collection,kind,customer_wallet,legacy_status,metadata,encrypted_payload)
      VALUES($1,'quote_api','pending_chain','quote-api-v1','deliveries','delivery',$2,'quote_pending','{}',$3)`,[context.id,customer.address.toLowerCase(),JSON.stringify(crypto.encrypt(payload,recordAad(context)))]);
    const data={...hub.deliveryAt(102),id:String(id),customer:customer.address.toLowerCase(),courier:courier.address.toLowerCase(),state:'InTransit',quoteDigest:hashOf(`ops-quote-${id}`)};
    await db.query('INSERT INTO monosfer.delivery_projections(stream,delivery_id,data,updated_block) VALUES($1,$2,$3,102)',[stream,id,JSON.stringify(data,(_,v)=>typeof v==='bigint'?String(v):v)]);
    // Isolated fixture for the trusted Phase 5 link; production writer remains the quote worker.
    await db.query('INSERT INTO monosfer.private_delivery_links(private_record_id,stream,delivery_id,quote_digest) VALUES($1,$2,$3,$4)',[context.id,stream,id,data.quoteDigest]);
  }
  const access=new DeliveryAccess(db,config);
  for(let id=0;id<2;id++)bindings.push(await access.withDelivery(String(id),customer.address,false,async ctx=>ctx.binding));
  const sharedDb={query:db.query.bind(db),transaction:db.transaction.bind(db),ping:db.ping.bind(db)};
  const sharedRedis=Object.fromEntries(['command','get','set','del','consume','increment','ping'].map(name=>[name,redis[name].bind(redis)]));
  const makeApp=async(options={})=>{const result=await testApplication({database:sharedDb,redis:sharedRedis,authRepository:stores.authRepository,usersRepository:stores.usersRepository,settings,...options});apps.push(result.app);return result;};
  const api=await makeApp();const sessions={};
  for(const [name,account]of Object.entries({customer,courier,other}))sessions[name]=await login(api.app,account);
  const headers=(name,extra={})=>({origin,cookie:sessions[name].cookie,'x-csrf-token':sessions[name].csrfToken,...extra});
  const createTracking=async(name,id='0')=>{
    const response=await api.app.inject({method:'POST',url:`/v1/deliveries/${id}/tracking/sessions`,headers:headers(name),payload:{}});
    assert.equal(response.statusCode,201);const data=response.json();tokens.push(data.trackingSession);return data;
  };
  const publish=(name,raw,input,id='0')=>api.app.inject({method:'POST',url:`/v1/deliveries/${id}/tracking/location`,headers:headers(name,{'x-tracking-session':raw}),payload:input});
  const read=(name,raw,id='0')=>api.app.inject({url:`/v1/deliveries/${id}/tracking/location`,headers:headers(name,{'x-tracking-session':raw})});
  const sample=(sequence=1)=>({lat:41.012345,lng:29.123456,sequence,capturedAt:new Date().toISOString(),accuracyMeters:4});
  return {...api,settings,config,db,redis,stream,recordIds,storage,access,bindings,stores,customer,courier,other,sessions,makeApp,headers,createTracking,publish,read,sample};
}
