import test from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { operationsFixture } from '../support/operations.mjs';
import { hash } from '../../dist/security/tokens.js';
import { RedisService } from '../../dist/infrastructure/redis.module.js';
import { TrackingStore } from '../../dist/tracking/store.js';

test('real tracking TTL, atomic sequence, delivery/session isolation and finalized lifecycle gates',{timeout:60000},async t=>{
  const f=await operationsFixture(t);
  const courier=await f.createTracking('courier');const viewer=await f.createTracking('customer');
  assert.equal(courier.mode,'publish');assert.equal(viewer.mode,'view');
  const sample=f.sample();const responses=await Promise.all([f.publish('courier',courier.trackingSession,sample),f.publish('courier',courier.trackingSession,sample)]);
  assert.deepEqual(responses.map(r=>r.statusCode),[201,201]);assert.deepEqual(responses[0].json(),responses[1].json());
  assert.equal((await f.read('customer',viewer.trackingSession)).json().location.lat,sample.lat);
  assert.equal((await f.publish('customer',viewer.trackingSession,f.sample(2))).statusCode,403);
  assert.equal((await f.read('other',viewer.trackingSession)).statusCode,403);
  assert.equal((await f.read('courier',viewer.trackingSession)).statusCode,403);
  assert.equal((await f.read('customer',viewer.trackingSession,'1')).statusCode,403);
  assert.equal((await f.publish('courier',courier.trackingSession,{...sample,lng:28})).statusCode,409);
  assert.equal((await f.publish('courier',courier.trackingSession,{...sample,sequence:2,capturedAt:new Date(Date.parse(sample.capturedAt)-1).toISOString()})).statusCode,409);
  assert.equal((await f.publish('courier',courier.trackingSession,{...sample,sequence:2,capturedAt:'2000-01-01T00:00:00Z'})).statusCode,400);
  const keys=await f.redis.command(c=>c.keys(`tracking:{${f.bindings[0]}}:*`));
  assert.ok(keys.length>3);assert.ok(keys.every(key=>!key.includes(courier.trackingSession)&&!key.includes(viewer.trackingSession)));
  const events=await f.redis.command(c=>c.xRange(`tracking:{${f.bindings[0]}}:events`,'-','+'));
  assert.equal(events.length,1);assert.equal(JSON.stringify(events).includes(String(sample.lat)),false);
  const ttl=await f.redis.command(c=>c.ttl(`tracking:{${f.bindings[0]}}:latest`));assert.ok(ttl>0&&ttl<=2);
  const rotated=await f.createTracking('customer');assert.equal((await f.read('customer',viewer.trackingSession)).statusCode,403);
  const revoke=await f.app.inject({method:'DELETE',url:'/v1/deliveries/0/tracking/sessions',headers:f.headers('customer',{'x-tracking-session':rotated.trackingSession})});
  assert.equal(revoke.statusCode,204);assert.equal((await f.read('customer',rotated.trackingSession)).statusCode,403);
  const active=await f.createTracking('customer');
  for(const change of ["status='error'","integrity_ok=false","checked_at=now()-interval '2 minutes'","observed_head=103",`export_fingerprint='${'a'.repeat(64)}'`]){
    await f.db.query(`UPDATE monosfer.indexer_streams SET ${change} WHERE stream=$1`,[f.stream]);
    assert.equal((await f.read('customer',active.trackingSession)).statusCode,403);
    await f.db.query("UPDATE monosfer.indexer_streams SET status='ready',integrity_ok=true,checked_at=now(),observed_head=102,export_fingerprint=$2 WHERE stream=$1",[f.stream,f.settings.indexer.fingerprint]);
  }
  for(const state of ['Completed','Cancelled','ReturnRequired']){
    await f.db.query("UPDATE monosfer.delivery_projections SET data=jsonb_set(data,'{state}',to_jsonb($2::text)) WHERE stream=$1 AND delivery_id=0",[f.stream,state]);
    assert.equal((await f.read('customer',active.trackingSession)).statusCode,403);
    assert.equal((await f.publish('courier',courier.trackingSession,f.sample(2))).statusCode,403);
  }
  await f.db.query("UPDATE monosfer.delivery_projections SET data=jsonb_set(data,'{state}','\"InTransit\"') WHERE stream=$1 AND delivery_id=0",[f.stream]);
  await f.db.query("UPDATE monosfer.delivery_projections SET data=jsonb_set(data,'{courier}',to_jsonb($2::text)) WHERE stream=$1 AND delivery_id=0",[f.stream,f.other.address.toLowerCase()]);
  assert.equal((await f.read('customer',active.trackingSession)).statusCode,403,'assignment change invalidates binding even for customer');
  assert.equal((await f.publish('courier',courier.trackingSession,f.sample(2))).statusCode,403);
  await f.db.query("UPDATE monosfer.delivery_projections SET data=jsonb_set(data,'{courier}',to_jsonb($2::text)) WHERE stream=$1 AND delivery_id=0",[f.stream,f.courier.address.toLowerCase()]);
  const connection=f.app.get(RedisService),command=connection.command;
  connection.command=async()=>{throw new Error('PRIVATE_REDIS_OUTAGE');};
  try{const unavailable=await f.read('customer',active.trackingSession);assert.equal(unavailable.statusCode,503);assert.ok(!unavailable.body.includes('PRIVATE_REDIS_OUTAGE'));}
  finally{connection.command=command;}
  await delay(2100);
  assert.equal((await f.read('customer',active.trackingSession)).json().location,null,'location expires without extending session');
  f.settings.operations.sessionTtl=1;const short=await f.createTracking('customer');await delay(1100);
  assert.equal((await f.read('customer',short.trackingSession)).statusCode,403);
  f.settings.operations.sessionTtl=30;const last=await f.createTracking('courier');
  await f.redis.del([`auth:session:${hash(f.sessions.courier.rawSession)}`]);
  assert.equal((await f.read('courier',last.trackingSession)).statusCode,401,'SIWE revocation invalidates delivery session');
  for(const secret of [courier.trackingSession,active.trackingSession,String(sample.lat),'OPS_PRIVATE_CODE'])assert.equal(f.logs.join('').includes(secret),false);
});

test('Redis tracking history is bounded and trimmed/future cursors reset to latest',{timeout:60000},async t=>{
  const f=await operationsFixture(t),tracking=await f.createTracking('courier'),store=f.app.get(TrackingStore);
  const scope=f.bindings[0],authHash=hash(f.sessions.courier.rawSession),raw=tracking.trackingSession;
  const keys=store.keys(scope,authHash,raw),value=await f.redis.get(keys.session);let last;
  for(let i=1;i<=132;i++)last=await store.publish(scope,authHash,raw,value,i,String(i),i,'{}',30,30);
  assert.equal((await f.redis.command(c=>c.xLen(`${keys.base}:events`))),128);
  for(const cursor of ['0-0','9999999999999999-0']){
    const result=await store.read(scope,authHash,raw,value,cursor);assert.equal(result.reset,true);assert.equal(result.events[0].id,last);
  }
  const current=await store.read(scope,authHash,raw,value,last);assert.equal(current.reset,false);assert.deepEqual(current.events,[]);
});

test('separate SSE instances share Redis, reconnect with cursor, reject excess connections and close on revoke/shutdown',{timeout:60000},async t=>{
  const f=await operationsFixture(t);const a=await f.makeApp({realtime:true}),b=await f.makeApp({realtime:true});
  assert.ok(a.document.paths['/v1/deliveries/{id}/tracking/events']);assert.equal(a.document.paths['/v1/quotes/delivery'],undefined);
  await a.app.listen(0,'127.0.0.1');await b.app.listen(0,'127.0.0.1');
  const courier=await f.createTracking('courier'),viewer=await f.createTracking('customer');
  const sample=f.sample();assert.equal((await f.publish('courier',courier.trackingSession,sample)).statusCode,201);
  const url=app=>`http://127.0.0.1:${app.getHttpServer().address().port}/v1/deliveries/0/tracking/events`;
  const live=[];
  t.after(async()=>{for(const controller of live)controller.abort();});
  const connect=async(app,after)=>{
    const controller=new AbortController();live.push(controller);
    const response=await fetch(url(app),{headers:f.headers('customer',{'x-tracking-session':viewer.trackingSession,...(after?{'Last-Event-ID':after}:{})}),signal:controller.signal});
    return {response,controller,reader:response.body.getReader()};
  };
  const until=async(reader,predicate)=>{
    let body='';for(let n=0;n<30;n++){const result=await reader.read();if(result.done)return body;body+=new TextDecoder().decode(result.value);if(predicate(body))return body;}
    throw new Error('Expected SSE event not observed');
  };
  const first=await connect(a.app);assert.equal(first.response.status,200);assert.match(first.response.headers.get('content-type'),/text\/event-stream/);
  const initial=await until(first.reader,body=>body.includes('event: location'));
  assert.ok(initial.includes(String(sample.lat)));const cursor=/id: ([0-9]+-[0-9]+)/.exec(initial)[1];
  const duplicate=await connect(b.app);assert.equal(duplicate.response.status,429);duplicate.controller.abort();
  first.controller.abort();await delay(200);
  await delay(2);const nextSample=f.sample(2);assert.equal((await f.publish('courier',courier.trackingSession,nextSample)).statusCode,201);
  const resumed=await connect(b.app,cursor);assert.equal(resumed.response.status,200);
  const resumedBody=await until(resumed.reader,body=>body.includes('event: location'));
  assert.ok(resumedBody.includes('"sequence":2'));assert.ok(!resumedBody.includes('"sequence":1'));
  await f.app.inject({method:'DELETE',url:'/v1/deliveries/0/tracking/sessions',headers:f.headers('customer',{'x-tracking-session':viewer.trackingSession})});
  assert.ok((await until(resumed.reader,body=>body.includes('event: closed'))).includes('access_unavailable'));resumed.controller.abort();
  const replacement=await f.createTracking('customer');viewer.trackingSession=replacement.trackingSession;
  const final=await connect(a.app,'0-0');assert.equal(final.response.status,200);
  assert.ok((await until(final.reader,body=>body.includes('event: reset'))).includes('event: reset'));
  await a.app.close();const end=await final.reader.read().catch(()=>({done:true}));assert.ok(end.done||end.value);
  final.controller.abort();
  assert.equal(await f.redis.get(`tracking:connection:${hash(viewer.trackingSession)}`),null,'shutdown releases shared connection lease');
});
