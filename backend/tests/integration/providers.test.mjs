import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { operationsFixture } from '../support/operations.mjs';
import { ProviderWorker } from '../../dist/providers/worker.js';
import { ProviderJobs } from '../../dist/providers/jobs.js';
import { EvidenceStorage, NotificationProvider, RouteProvider, checksum } from '../../dist/providers/adapters.js';

test('encrypted route/evidence and durable notification workers: real SQL, object storage, retry and ownership',{timeout:60000},async t=>{
  const f=await operationsFixture(t);const worker=f.app.get(ProviderWorker),storage=f.app.get(EvidenceStorage),route=f.app.get(RouteProvider);
  const upload=(input,key=randomUUID(),who='courier')=>f.app.inject({method:'POST',url:'/v1/deliveries/0/evidence',headers:f.headers(who,{'idempotency-key':key}),payload:input});
  const metadata=(id,who='courier',content=false)=>f.app.inject({url:`/v1/deliveries/0/evidence/${id}${content?'/content':''}`,headers:f.headers(who)});
  const inbox=(who='customer',query='')=>f.app.inject({url:`/v1/notifications${query}`,headers:f.headers(who)});
  await t.test('enqueue failure rolls back evidence issuance without leaking the error',async()=>{
    const jobs=f.app.get(ProviderJobs),enqueue=jobs.enqueue.bind(jobs),key=randomUUID();
    jobs.enqueue=async()=>{throw new Error('PRIVATE_QUEUE_ERROR');};
    try{
      const result=await upload({contentType:'text/plain',text:'ROLLBACK_EVIDENCE'},key);
      assert.equal(result.statusCode,503);assert.ok(!result.body.includes('PRIVATE_QUEUE_ERROR'));
      assert.equal((await f.db.query('SELECT count(*)::int AS n FROM monosfer.evidence_packages WHERE stream=$1',[f.stream])).rows[0].n,0);
    }finally{jobs.enqueue=enqueue;}
  });
  await t.test('route derives coordinates from private data and cache fails closed after expiry/provider outage',async()=>{
    const request=who=>f.app.inject({url:'/v1/deliveries/0/route',headers:f.headers(who)});
    assert.equal((await request('other')).statusCode,403);
    const estimate=await request('customer');assert.equal(estimate.statusCode,200);assert.equal(estimate.json().provider,'straight-line-dev');
    const cached=await f.redis.get(`route:${f.bindings[0]}`);assert.ok(cached);assert.equal(cached.includes('OPS_PRIVATE'),false);
    const original=route.estimate.bind(route);route.estimate=async()=>{throw new Error('SECRET_ROUTE_PROVIDER');};
    try{
      assert.deepEqual((await request('courier')).json(),estimate.json(),'authorized users share encrypted route cache');
      await f.redis.del([`route:${f.bindings[0]}`]);const error=await request('customer');assert.equal(error.statusCode,503);assert.ok(!error.body.includes('SECRET_ROUTE_PROVIDER'));
      route.estimate=async()=>({provider:'bad',distanceMeters:1,durationSeconds:1,estimatedAt:'2000-01-01T00:00:00Z'});
      assert.equal((await request('customer')).statusCode,503);
    }finally{route.estimate=original;}
  });
  let evidence;
  const input={contentType:'text/plain',text:'PRIVATE_EVIDENCE_CONTENT',gps:{lat:41.123456789,lng:29.234567891,capturedAt:new Date().toISOString()}};
  await t.test('evidence issuance is idempotent and stored encrypted; content is owner-only',async()=>{
    const key=randomUUID();const responses=await Promise.all([upload(input,key),upload(input,key)]);
    assert.deepEqual(responses.map(r=>r.statusCode),[201,201]);assert.deepEqual(responses[0].json(),responses[1].json());evidence=responses[0].json();
    assert.equal(evidence.status,'pending');assert.equal((await metadata(evidence.evidenceId,'courier',true)).statusCode,409);
    assert.equal((await upload({...input,text:'different'},key)).statusCode,409);
    assert.equal((await metadata(evidence.evidenceId,'customer')).statusCode,403,'even paying customer cannot read another submitter evidence');
    assert.equal((await metadata(evidence.evidenceId,'other',true)).statusCode,403);
    const packages=await f.db.query('SELECT * FROM monosfer.evidence_packages WHERE stream=$1',[f.stream]);assert.equal(packages.rows.length,1);
    const jobs=await f.db.query('SELECT * FROM monosfer.provider_jobs WHERE stream=$1',[f.stream]);assert.equal(jobs.rows.length,1);
    assert.ok(!JSON.stringify([packages.rows,jobs.rows]).includes(input.text));
    assert.equal((await upload(input,randomUUID(),'other')).statusCode,403);
  });
  await t.test('failure after storage side effect retries same immutable object and creates one ready notification',async()=>{
    const original=storage.put.bind(storage);let fail=true;
    storage.put=async(...args)=>{await original(...args);if(fail){fail=false;throw new Error('PRIVATE_PROVIDER_FAILURE');}};
    try{
      const first=await worker.once();assert.ok(first.failed>=1);
      assert.equal((await metadata(evidence.evidenceId)).json().status,'pending');
      const object=await readFile(join(storage.root,`${evidence.evidenceId}.json`),'utf8');assert.ok(!object.includes(input.text));assert.ok(!object.includes(String(input.gps.lat)));
      await f.db.query('UPDATE monosfer.provider_jobs SET next_attempt_at=now() WHERE evidence_id=$1',[evidence.evidenceId]);
      await Promise.all([worker.once(),worker.once()]);
      assert.equal((await metadata(evidence.evidenceId)).json().status,'ready');
      const content=await metadata(evidence.evidenceId,'courier',true);assert.equal(content.statusCode,200);assert.equal(content.json().text,input.text);
      assert.equal(content.json().evidenceHash,checksum(input.text));
      const count=await f.db.query("SELECT count(*)::int AS n FROM monosfer.notifications WHERE stream=$1 AND template='evidence_ready'",[f.stream]);assert.equal(count.rows[0].n,1);
      await worker.once();assert.equal((await f.db.query('SELECT count(*)::int AS n FROM monosfer.evidence_packages WHERE stream=$1',[f.stream])).rows[0].n,1);
    }finally{storage.put=original;}
  });
  await t.test('ciphertext tampering, pending/failed content and cross-delivery object access are rejected',async()=>{
    const original=storage.get.bind(storage);storage.get=async()=>'{"tampered":true}';
    try{assert.equal((await metadata(evidence.evidenceId,'courier',true)).statusCode,503);}finally{storage.get=original;}
    assert.equal((await f.app.inject({url:`/v1/deliveries/1/evidence/${evidence.evidenceId}/content`,headers:f.headers('courier')})).statusCode,404);
    const bad=await upload({contentType:'text/plain',text:'FAILURE_TEST_EVIDENCE'});const id=bad.json().evidenceId;
    const put=storage.put.bind(storage);storage.put=async()=>{throw new Error('SECRET_STORAGE_DOWN');};
    try{
      for(let n=0;n<3;n++){await f.db.query('UPDATE monosfer.provider_jobs SET next_attempt_at=now() WHERE evidence_id=$1',[id]);await worker.once();}
      assert.equal((await metadata(id)).json().status,'failed');assert.equal((await metadata(id,'courier',true)).statusCode,409);
      const job=(await f.db.query('SELECT attempts,status,last_error FROM monosfer.provider_jobs WHERE evidence_id=$1',[id])).rows[0];
      assert.deepEqual(job,{attempts:3,status:'failed',last_error:'PROVIDER_UNAVAILABLE'});
    }finally{storage.put=put;}
  });
  await t.test('notification at-least-once retry uses stable idempotency key and inbox is wallet-scoped/paginated',async()=>{
    const provider=f.app.get(NotificationProvider);const send=provider.send.bind(provider);const delivered=new Set();let fail=true;
    provider.send=async(id)=>{delivered.add(id);if(fail){fail=false;throw new Error('SECRET_NOTIFICATION_OUTAGE');}};
    await f.db.query("UPDATE monosfer.delivery_projections SET data=jsonb_set(data,'{state}','\"DeliveredPending\"') WHERE stream=$1 AND delivery_id=0",[f.stream]);
    try{
      assert.ok((await worker.once()).failed>=1);
      const pending=(await f.db.query("SELECT id FROM monosfer.provider_jobs WHERE stream=$1 AND kind='notification.send' AND status='pending'",[f.stream])).rows;
      assert.equal(pending.length,1);await f.db.query('UPDATE monosfer.provider_jobs SET next_attempt_at=now() WHERE id=$1',[pending[0].id]);
      await worker.once();assert.equal(delivered.size,2,'two participants, retries do not create a third logical delivery');
      const first=(await inbox('customer','?limit=1')).json();assert.equal(first.data.length,1);assert.ok(first.nextCursor);
      const next=(await inbox('customer',`?limit=1&before=${first.nextCursor}`)).json();assert.equal(next.data.length,1);assert.notEqual(first.data[0].id,next.data[0].id);
      assert.equal((await inbox('other')).json().data.length,0);
      const visible=await inbox('customer');assert.ok(!visible.body.includes(input.text));
      await f.db.query("UPDATE monosfer.indexer_streams SET status='error' WHERE stream=$1",[f.stream]);
      assert.equal((await inbox('customer')).json().data.length,0);
      assert.equal((await metadata(evidence.evidenceId,'courier',true)).statusCode,403);
      await f.db.query("UPDATE monosfer.indexer_streams SET status='ready' WHERE stream=$1",[f.stream]);
    }finally{provider.send=send;}
  });
  for(const secret of [input.text,String(input.gps.lat),'SECRET_ROUTE_PROVIDER','SECRET_STORAGE_DOWN','SECRET_NOTIFICATION_OUTAGE'])assert.equal(f.logs.join('').includes(secret),false);
});
