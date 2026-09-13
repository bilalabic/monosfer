import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { runner } from 'node-pg-migrate';
import { quoteFixture, quoteRpcServer, quoteInput } from '../support/quotes.mjs';
import { rpcServer, hashOf } from '../support/indexer.mjs';
import { authApplication, login, origin } from '../support/auth.mjs';
import { DatabaseService } from '../../dist/infrastructure/database.module.js';
import { RedisService } from '../../dist/infrastructure/redis.module.js';
import { ConfigService } from '../../dist/config/config.js';
import { hash } from '../../dist/security/tokens.js';
import { QuoteChain } from '../../dist/quotes/chain.js';
import { QuotesRepository } from '../../dist/quotes/quotes.repository.js';
import { QuoteLinkWorker } from '../../dist/quotes/link-worker.js';
import { PrivateDataCrypto, recordAad } from '../../dist/private-data/crypto.js';
import { PrivateDataService, PrivateDeliveryProjection, PrivateRecordsRepository } from '../../dist/private-data/private-data.module.js';
import { IndexerWorker } from '../../dist/indexer/worker.js';
import { HubRpc } from '../../dist/indexer/rpc.js';
import { createImportPool } from '../../dist/private-data/importer.js';

test('phase 5 real PostgreSQL + read-only RPC: issuance, concurrency, rollback, projection links and refresh',{timeout:90000},async t=>{
  const f=quoteFixture();const url=process.env.DATABASE_URL??'postgresql://monosfer:local-development-only@127.0.0.1:55432/monosfer_v2';
  assert.ok(['127.0.0.1','localhost'].includes(new URL(url).hostname));
  assert.ok(['/monosfer_v2','/monosfer_v2_test'].includes(new URL(url).pathname));
  const migration={databaseUrl:url,dir:fileURLToPath(new URL('../../migrations',import.meta.url)),direction:'up',migrationsTable:'pgmigrations',log:()=>{}};
  await runner(migration);assert.deepEqual(await runner(migration),[]);
  f.settings.databaseUrl=url;f.settings.connectionTimeoutMs=2000;
  const db=new DatabaseService(f.config);const pool=createImportPool(url);
  const rpc=await quoteRpcServer(f);const indexRpc=await rpcServer(f.hub);
  const repository=new QuotesRepository(db,f.config);const worker=new QuoteLinkWorker(f.config,repository);
  const {app,logs}=await authApplication({database:db,settings:f.settings,providers:[[QuoteChain,f.chain]]});
  const customer=f.account.address.toLowerCase();const stream=`10143:${f.hub.address}`;
  t.after(async()=>{
    t.mock.timers.reset();await app.close();await rpc.close();await indexRpc.close();
    try{
      // Exact random test customer + random stream only; no user/legacy data is selected.
      await pool.query('DELETE FROM monosfer.private_delivery_links WHERE stream=$1',[stream]);
      for(const table of ['idempotency_keys','transactional_outbox','risk_quote_inputs'])await pool.query(`DELETE FROM monosfer.${table} WHERE quote_digest IN (SELECT digest FROM monosfer.risk_quote_issuances WHERE customer=$1 AND stream=$2)`,[customer,stream]);
      await pool.query('DELETE FROM monosfer.risk_quote_issuances WHERE customer=$1 AND stream=$2',[customer,stream]);
      await pool.query("DELETE FROM monosfer.private_delivery_records WHERE customer_wallet=$1 AND source='quote_api'",[customer]);
      for(const table of ['bid_projections','delivery_projections','chain_event_inbox','indexer_blocks','indexer_streams'])await pool.query(`DELETE FROM monosfer.${table} WHERE stream=$1`,[stream]);
    }finally{await pool.end();}
  });
  const session=await login(app,f.account);const other=await login(app);
  const headers={origin,cookie:session.cookie,'x-csrf-token':session.csrfToken};
  const payload=quoteInput();const key=randomUUID();
  const post=(input=payload,k=randomUUID())=>app.inject({method:'POST',url:'/v1/quotes/delivery',headers:{...headers,'idempotency-key':k},payload:input});
  const refresh=(q,k=randomUUID(),h=headers)=>app.inject({method:'POST',url:`/v1/quotes/${q.quoteDigest}/refresh`,headers:{...h,'idempotency-key':k},payload:{}});
  const status=(q,cookie=session.cookie)=>app.inject({url:`/v1/quotes/${q.quoteDigest}`,headers:{cookie}});
  const count=async(table,where='customer=$1',values=[customer])=>(await pool.query(`SELECT count(*)::int AS n FROM monosfer.${table} WHERE ${where}`,values)).rows[0].n;
  let issued;
  await t.test('concurrent identical requests return the same signed response; changed private body conflicts',async()=>{
    const responses=await Promise.all([post(payload,key),post(payload,key),post(payload,key)]);
    assert.deepEqual(responses.map(r=>r.statusCode),[201,201,201]);issued=responses[0].json();
    for(const result of responses)assert.deepEqual(result.json(),issued);
    assert.equal(await count('risk_quote_issuances'),1);
    assert.equal(await count('private_delivery_records','customer_wallet=$1'),1);
    const counts=await pool.query(`SELECT (SELECT count(*) FROM monosfer.risk_quote_inputs WHERE quote_digest=$1)::int AS inputs,
      (SELECT count(*) FROM monosfer.idempotency_keys WHERE quote_digest=$1)::int AS keys,
      (SELECT count(*) FROM monosfer.transactional_outbox WHERE quote_digest=$1)::int AS outbox`,[issued.quoteDigest]);
    assert.deepEqual(counts.rows[0],{inputs:1,keys:1,outbox:1});
    assert.equal((await post({...payload,privatePayload:{...payload.privatePayload,notes:'changed-private'}},key)).statusCode,409);
    const reordered={privatePayload:payload.privatePayload,metadata:{urgency:'standard',packageType:'document'},declaredValue:'10000'};
    assert.deepEqual((await post(reordered,key)).json(),issued);
    f.minBps=10000;assert.equal((await post(payload,key)).statusCode,409,'changed policy invalidates cached quote');f.minBps=7500;
    // Issuance TTL is created/checked with the application clock. Docker's clock can differ from the host.
    await pool.query('UPDATE monosfer.idempotency_keys SET expires_at=$2 WHERE quote_digest=$1',[issued.quoteDigest,new Date(Date.now()-1000)]);
    assert.equal((await post(payload,key)).statusCode,409,'expired key is a tombstone, not a new issuance');
    await pool.query("UPDATE monosfer.idempotency_keys SET expires_at=now()+interval '1 day' WHERE quote_digest=$1",[issued.quoteDigest]);
    const record=(await pool.query('SELECT * FROM monosfer.private_delivery_records WHERE id=$1',[issued.privateRecordId])).rows[0];
    assert.equal(record.source,'quote_api');assert.equal(record.verification_status,'pending_chain');assert.equal(record.legacy_mongo_id,null);assert.equal(record.import_run_id,null);
    assert.ok(!JSON.stringify(record).includes('QUOTE_PRIVATE'));
    assert.deepEqual(new PrivateDataCrypto(f.settings).decrypt(record.encrypted_payload,recordAad(record)),payload.privatePayload);
    const idem=(await pool.query('SELECT * FROM monosfer.idempotency_keys WHERE quote_digest=$1',[issued.quoteDigest])).rows[0];
    for(const secret of [key,issued.signature,issued.quote.salt,'QUOTE_PRIVATE'])assert.ok(!JSON.stringify(idem).includes(secret));
  });
  await t.test('HTTP owner isolation, read response minimization, tampered data and unavailable signer rollback',async()=>{
    const result=await status(issued);assert.equal(result.statusCode,200);assert.equal(result.json().status,'issued');
    for(const field of ['signature','quote','typedData','privatePayload'])assert.equal(result.json()[field],undefined);
    assert.equal((await status(issued,other.cookie)).statusCode,403);
    assert.equal((await refresh(issued,randomUUID(),{origin,cookie:other.cookie,'x-csrf-token':other.csrfToken})).statusCode,403);
    assert.equal((await status({quoteDigest:hashOf('missing')})).statusCode,404);
    for(const key of ['badHash','badSigner','fail']){
      f[key]=true;const response=await post();assert.equal(response.statusCode,503);f[key]=false;
      assert.equal(response.body.includes('QUOTE_RPC_PRIVATE_SECRET'),false);
    }
    assert.equal(await count('risk_quote_issuances'),1);assert.equal(await count('private_delivery_records','customer_wallet=$1'),1);
    assert.equal((await refresh(issued)).statusCode,409,'unexpired quote cannot be refreshed');
  });
  await t.test('outbox writes roll back together even after INSERT; retry recovers without half records',async()=>{
    let reject=true;
    const failingDb={transaction:work=>db.transaction(client=>work({query:async(sql,args)=>{
      const result=await client.query(sql,args);if(reject&&sql.includes('INSERT INTO monosfer.transactional_outbox'))throw new Error('PRIVATE_SQL_FAILURE');return result;
    }}))};
    const failingApp=await authApplication({database:failingDb,settings:f.settings,providers:[[QuoteChain,f.chain]]});
    try{
      const auth=await login(failingApp.app,f.account);const k=randomUUID();
      const request=()=>failingApp.app.inject({method:'POST',url:'/v1/quotes/delivery',headers:{origin,cookie:auth.cookie,'x-csrf-token':auth.csrfToken,'idempotency-key':k},payload});
      const response=await request();assert.equal(response.statusCode,503);assert.ok(!response.body.includes('PRIVATE_SQL_FAILURE'));
      assert.equal(await count('risk_quote_issuances'),1);assert.equal(await count('private_delivery_records','customer_wallet=$1'),1);
      reject=false;const retried=await request();assert.equal(retried.statusCode,201);assert.deepEqual((await request()).json(),retried.json());
    }finally{await failingApp.app.close();}
  });
  const retryDue=()=>pool.query(`UPDATE monosfer.transactional_outbox SET next_attempt_at=now() WHERE quote_digest=$1`,[issued.quoteDigest]);
  const resolver=new PrivateDeliveryProjection(db,f.config);
  await t.test('no finalized projection means no link; indexer consumes actual DeliveryCreated log',async()=>{
    assert.equal((await worker.once()).linked,0);assert.equal(await resolver.findConfirmed(issued.privateRecordId),null);
    f.hub.logs.set(100n,[]);
    f.hub.event(100,'DeliveryCreated',{deliveryId:0n,customer,riskTier:issued.quote.riskTier,requiredCollateral:BigInt(issued.quote.requiredCoverage),deadline:1000n,quoteDigest:issued.quoteDigest});
    f.hub.event(100,'StateChanged',{deliveryId:0n,from:0,to:1,deadline:1000n});
    const indexer=new IndexerWorker(pool,new HubRpc(indexRpc.url),f.hub.bundle,{...f.hub.settings,rpcUrl:indexRpc.url});
    await indexer.once();await indexer.once();
    assert.equal((await pool.query('SELECT status FROM monosfer.indexer_streams WHERE stream=$1',[stream])).rows[0].status,'ready');
    assert.equal(await resolver.findConfirmed(issued.privateRecordId),null);
  });
  await t.test('stale/error/integrity/lag/fingerprint/wallet/digest mismatch cannot establish private ownership',async()=>{
    const badStream=["checked_at=now()-interval '2 minutes'","status='error'","integrity_ok=false","observed_head=last_block+1",`export_fingerprint='${'b'.repeat(64)}'`];
    for(const change of badStream){
      await pool.query(`UPDATE monosfer.indexer_streams SET ${change} WHERE stream=$1`,[stream]);await retryDue();
      assert.equal((await worker.once()).linked,0);assert.equal(await resolver.findConfirmed(issued.privateRecordId),null);
      await pool.query(`UPDATE monosfer.indexer_streams SET checked_at=now(),status='ready',integrity_ok=true,observed_head=last_block,export_fingerprint=$2 WHERE stream=$1`,[stream,f.settings.indexer.fingerprint]);
    }
    for(const [field,value]of [['customer',other.user.walletAddress.toLowerCase()],['quoteDigest',hashOf('wrong-quote')]]){
      const correct=field==='customer'?customer:issued.quoteDigest;
      await pool.query('UPDATE monosfer.delivery_projections SET data=jsonb_set(data,ARRAY[$2],to_jsonb($3::text)) WHERE stream=$1',[stream,field,value]);
      await retryDue();assert.equal((await worker.once()).linked,0);
      await pool.query('UPDATE monosfer.delivery_projections SET data=jsonb_set(data,ARRAY[$2],to_jsonb($3::text)) WHERE stream=$1',[stream,field,correct]);
    }
    await pool.query('UPDATE monosfer.risk_quote_issuances SET export_fingerprint=$2 WHERE digest=$1',[issued.quoteDigest,'c'.repeat(64)]);
    await retryDue();assert.equal((await worker.once()).linked,0);
    await pool.query('UPDATE monosfer.risk_quote_issuances SET export_fingerprint=$2 WHERE digest=$1',[issued.quoteDigest,f.settings.indexer.fingerprint]);
    assert.equal(await count('private_delivery_links','private_record_id=$1',[issued.privateRecordId]),0);
  });
  await t.test('worker failure after link INSERT rolls back; concurrent retries create exactly one durable binding',async()=>{
    await retryDue();
    const failing={transaction:work=>db.transaction(client=>work({query:async(sql,args)=>{
      const result=await client.query(sql,args);if(sql.includes('INSERT INTO monosfer.private_delivery_links'))throw new Error('PRIVATE_WORKER_FAILURE');return result;
    }}))};
    const broken=new QuoteLinkWorker(f.config,new QuotesRepository(failing,f.config));
    await assert.rejects(broken.once(),e=>e.getStatus()===503);
    assert.equal(await count('private_delivery_links','private_record_id=$1',[issued.privateRecordId]),0);
    const batches=await Promise.all([worker.once(),worker.once()]);assert.equal(batches.reduce((sum,r)=>sum+r.linked,0),1);
    await pool.query("UPDATE monosfer.transactional_outbox SET status='pending',next_attempt_at=now() WHERE quote_digest=$1",[issued.quoteDigest]);
    await worker.once();assert.equal(await count('private_delivery_links','private_record_id=$1',[issued.privateRecordId]),1);
    assert.equal((await status(issued)).json().status,'linked');assert.equal((await status(issued)).json().deliveryId,'0');
    const privateService=new PrivateDataService(new PrivateRecordsRepository(db),new PrivateDataCrypto(f.settings),resolver);
    assert.equal((await privateService.readDelivery(issued.privateRecordId,customer)).dropoff.deliveryCode,'QUOTE_PRIVATE_CODE');
    assert.equal((await privateService.readDelivery(issued.privateRecordId,f.hub.courier)).dropoff.deliveryCode,undefined);
    assert.equal((await privateService.readDelivery(issued.privateRecordId,f.hub.courier)).dropoff.contactPhone,'+905552345678');
    await assert.rejects(privateService.readDelivery(issued.privateRecordId,other.user.walletAddress),e=>e.getStatus()===403);
  });
  await t.test('refresh waits past finalized inclusive expiry, rejects redeemed/linked and serializes child issuance',async()=>{
    const unused=(await post()).json();const redeemed=(await post()).json();
    f.redeemed.add(redeemed.quoteDigest);f.redeemed.add(issued.quoteDigest);
    const expiry=Number(unused.quote.expiresAt)*1000;
    t.mock.timers.enable({apis:['Date'],now:expiry});
    assert.equal((await refresh(unused)).statusCode,409,'contract expiry second remains redeemable');
    t.mock.timers.setTime(expiry+1000);
    assert.equal((await refresh(redeemed)).statusCode,409,'redeemed without a projected link still rejects');
    assert.equal((await refresh(issued)).statusCode,409,'linked record never refreshes');
    assert.equal((await post(payload,key)).statusCode,409,'expired idempotent response never mints another quote');
    const refreshKeys=[randomUUID(),randomUUID()];const results=await Promise.all(refreshKeys.map(k=>refresh(unused,k)));
    assert.deepEqual(results.map(r=>r.statusCode).sort(),[201,409]);const index=results.findIndex(r=>r.statusCode===201);
    const child=results[index].json();assert.notEqual(child.quoteDigest,unused.quoteDigest);assert.notEqual(child.quote.salt,unused.quote.salt);
    assert.equal(child.privateRecordId,unused.privateRecordId);
    assert.deepEqual((await refresh(unused,refreshKeys[index])).json(),child);
    assert.equal((await status(unused)).json().status,'refreshed');
    assert.equal((await refresh(child)).statusCode,409);
    assert.equal(await count('risk_quote_issuances','private_record_id=$1',[unused.privateRecordId]),2);
    // Simulate link replay after quote expiry. Only this test's link is removed.
    await pool.query('DELETE FROM monosfer.private_delivery_links WHERE private_record_id=$1',[issued.privateRecordId]);
    await pool.query("UPDATE monosfer.transactional_outbox SET status='pending',next_attempt_at=now() WHERE quote_digest=$1",[issued.quoteDigest]);
    assert.ok(Date.now()>Date.parse(issued.expiresAt));
    assert.equal((await worker.once()).linked,1,'finalized chain acceptance still links an expired quote');
    t.mock.timers.reset();
  });
  await t.test('quote routes use real Redis rate counters and fail safely during Redis outage',async()=>{
    const redisUrl=process.env.REDIS_URL??'redis://:local-development-only@127.0.0.1:56379';
    assert.ok(['127.0.0.1','localhost'].includes(new URL(redisUrl).hostname));
    const rateSettings={...f.settings,redisUrl,authRateLimitMax:3};
    const redis=new RedisService(new ConfigService(rateSettings));
    // A unique synthetic remote IP isolates the counter; spoofed forwarded headers are ignored.
    const ip=`198.18.${Math.floor(Math.random()*255)}.${Math.floor(Math.random()*254)+1}`;
    const sharedDb={ping:db.ping.bind(db),query:db.query.bind(db),transaction:db.transaction.bind(db)};
    const rateApp=await authApplication({database:sharedDb,redis,settings:rateSettings,providers:[[QuoteChain,f.chain]]});
    try{
      const request=()=>rateApp.app.inject({method:'POST',url:'/v1/quotes/delivery',remoteAddress:ip,headers:{origin},payload});
      for(let i=0;i<3;i++)assert.equal((await request()).statusCode,401);
      const limited=await request();assert.equal(limited.statusCode,429);assert.ok(limited.headers['retry-after']);
      await redis.del([`auth:rate:${hash(ip)}`]);redis.onApplicationShutdown();
      const unavailable=await request();assert.equal(unavailable.statusCode,503);assert.equal(unavailable.body.includes('local-development-only'),false);
      assert.equal((await rateApp.app.inject('/v1/health/ready')).statusCode,503);
      // This app shares the test DB provider; avoid closing it before outer test cleanup.
    }finally{await rateApp.app.close();}
  });
  for(const secret of ['QUOTE_PRIVATE','QUOTE_RPC_PRIVATE_SECRET','PRIVATE_WORKER_FAILURE',issued.signature,issued.quote.salt,f.signerKey])assert.equal(logs.join('').includes(secret),false);
  assert.equal(f.requests.some(method=>/send|sign/i.test(method)),false);
  assert.equal(f.hub.requests.some(method=>/send|sign/i.test(method)),false);
});
