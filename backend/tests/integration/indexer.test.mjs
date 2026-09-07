import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { runner } from 'node-pg-migrate';
import { fileURLToPath } from 'node:url';
import { IndexerWorker } from '../../dist/indexer/worker.js';
import { HubRpc } from '../../dist/indexer/rpc.js';
import { createImportPool } from '../../dist/private-data/importer.js';
import { PrivateDataCrypto, parsePrivateKey, recordAad } from '../../dist/private-data/crypto.js';
import { PrivateDeliveryProjection, PrivateDataService, PrivateRecordsRepository } from '../../dist/private-data/private-data.module.js';
import { IndexerReadRepository } from '../../dist/indexer/read.module.js';
import { ConfigService, parseSettings } from '../../dist/config/config.js';
import { authEnv } from '../support/env.mjs';
import { testApplication, testEnv } from '../support/app.mjs';
import { hubFixture, rpcServer, hashOf } from '../support/indexer.mjs';

test('real SQL + RPC indexer: atomic ingest, restart, replay, reconcile, reorg, lag and private ownership', {timeout:90000}, async t=>{
  const url=process.env.DATABASE_URL??'postgresql://monosfer:local-development-only@127.0.0.1:55432/monosfer_v2';
  assert.ok(['127.0.0.1','localhost'].includes(new URL(url).hostname));
  assert.ok(['/monosfer_v2','/monosfer_v2_test'].includes(new URL(url).pathname));
  const migration={databaseUrl:url,dir:fileURLToPath(new URL('../../migrations',import.meta.url)),direction:'up',migrationsTable:'pgmigrations',log:()=>{}};
  await runner(migration);assert.deepEqual(await runner(migration),[]);
  const pool=createImportPool(url);const f=hubFixture();const server=await rpcServer(f);
  f.settings.rpcUrl=server.url;
  const rpc=new HubRpc(server.url);const worker=new IndexerWorker(pool,rpc,f.bundle,f.settings);
  const stream=worker.stream; const runId=randomUUID(); const privateId=randomUUID();
  const config=new ConfigService({...parseSettings(testEnv),indexer:f.settings});
  const db={query:pool.query.bind(pool),transaction:async work=>{
    const client=await pool.connect();try{await client.query('BEGIN');const result=await work(client);await client.query('COMMIT');return result;}
    catch(error){await client.query('ROLLBACK');throw error;}finally{client.release();}
  }};
  const reads=new IndexerReadRepository(db,config);
  const resolver=new PrivateDeliveryProjection(db,config);
  const crypto=new PrivateDataCrypto(parsePrivateKey(authEnv));
  const privateService=new PrivateDataService(new PrivateRecordsRepository(db),crypto,resolver);
  const {app,logs}=await testApplication({database:db,settings:{indexer:f.settings}});
  t.after(async()=>{
    await app.close();await server.close();
    try {
      // Only this test's random contract stream and private fixture are removed.
      await pool.query('DELETE FROM monosfer.private_delivery_links WHERE private_record_id=$1',[privateId]);
      for(const table of ['bid_projections','delivery_projections','chain_event_inbox','indexer_blocks','indexer_streams']) await pool.query(`DELETE FROM monosfer.${table} WHERE stream=$1`,[stream]);
      await pool.query('DELETE FROM monosfer.private_delivery_records WHERE id=$1',[privateId]);
      await pool.query('DELETE FROM monosfer.private_data_import_runs WHERE id=$1',[runId]);
    }finally{await pool.end();}
  });
  assert.equal((await reads.read('status')).indexing.status,'indexing_pending');
  assert.equal((await app.inject('/v1/deliveries/0')).statusCode,202);
  f.corrupt=true;await assert.rejects(worker.once(),{message:'Indexer operation failed'});
  assert.equal((await pool.query('SELECT last_block FROM monosfer.indexer_streams WHERE stream=$1',[stream])).rows[0].last_block,'99');
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM monosfer.chain_event_inbox WHERE stream=$1',[stream])).rows[0].n,0);
  f.corrupt=false;
  assert.equal((await worker.once()).indexedBlock,'101');
  assert.equal((await reads.read('status')).indexing.status,'syncing');
  assert.equal((await reads.read('delivery','0')).data.state,'AwaitingFunding');
  const resumed=new IndexerWorker(pool,rpc,f.bundle,f.settings);
  assert.equal((await resumed.once()).indexedBlock,'102');
  assert.equal((await reads.read('status')).indexing.status,'ready');
  const count=(await pool.query('SELECT count(*)::int AS n FROM monosfer.chain_event_inbox WHERE stream=$1',[stream])).rows[0].n;
  await resumed.once();assert.equal((await pool.query('SELECT count(*)::int AS n FROM monosfer.chain_event_inbox WHERE stream=$1',[stream])).rows[0].n,count);
  const firstPage=await reads.read('bids','0',1);assert.equal(firstPage.data.length,1);assert.ok(firstPage.nextCursor);
  const secondPage=await reads.read('bids','0',1,firstPage.nextCursor);assert.equal(secondPage.data.length,1);assert.equal(secondPage.nextCursor,null);
  assert.equal((await app.inject('/v1/deliveries/999')).statusCode,404);
  const detail=(await app.inject('/v1/deliveries/0')).json();assert.equal(detail.data.state,'ReadyForPickup');assert.equal(detail.data.courierAsk,'200');

  const context={id:privateId,source_namespace:'indexer-fixture',source_collection:'deliveries',legacy_mongo_id:randomUUID().replaceAll('-','').slice(0,24),kind:'delivery',schema_version:1};
  const payload={pickup:{address:'PRIVATE_ADDRESS',lat:41,lng:29},dropoff:{address:'PRIVATE_ADDRESS',deliveryCode:'PRIVATE_CODE'}};
  await pool.query("INSERT INTO monosfer.private_data_import_runs(id,source_namespace,mode,status) VALUES($1,'indexer-fixture','apply','completed')",[runId]);
  await pool.query(`INSERT INTO monosfer.private_delivery_records(id,source_namespace,source_collection,legacy_mongo_id,kind,customer_wallet,legacy_status,metadata,encrypted_payload,import_run_id)
    VALUES($1,$2,$3,$4,'delivery',$5,'Accepted','{}',$6,$7)`,[privateId,context.source_namespace,context.source_collection,context.legacy_mongo_id,f.customer,JSON.stringify(crypto.encrypt(payload,recordAad(context))),runId]);
  assert.equal(await resolver.findConfirmed(privateId),null,'legacy wallet/ID alone never creates a binding');
  // Test fixture for a future trusted quote issuance binding; there is no application/API link writer.
  await pool.query('INSERT INTO monosfer.private_delivery_links(private_record_id,stream,delivery_id,quote_digest) VALUES($1,$2,0,$3)',[privateId,stream,hashOf('quote')]);
  assert.equal((await privateService.readDelivery(privateId,f.customer)).dropoff.deliveryCode,'PRIVATE_CODE');
  assert.equal((await privateService.readDelivery(privateId,f.courier)).dropoff.deliveryCode,undefined);
  await assert.rejects(privateService.readDelivery(privateId,f.other),error=>error.getStatus()===403);
  await pool.query("UPDATE monosfer.indexer_streams SET checked_at=now()-interval '2 minutes' WHERE stream=$1",[stream]);
  assert.equal((await reads.read('status')).indexing.status,'stale');assert.equal(await resolver.findConfirmed(privateId),null);
  await resumed.once();
  await pool.query('UPDATE monosfer.private_delivery_links SET quote_digest=$2 WHERE private_record_id=$1',[privateId,hashOf('wrong-quote')]);
  assert.equal(await resolver.findConfirmed(privateId),null);
  await pool.query('UPDATE monosfer.private_delivery_links SET quote_digest=$2 WHERE private_record_id=$1',[privateId,hashOf('quote')]);

  const report=await resumed.reconcile();assert.deepEqual(report,{checkedDeliveries:1,checkedBids:2,mismatches:0});await resumed.once();
  // Missing bid projection must be detected even though the remaining known bids match bidOf.
  await pool.query('DELETE FROM monosfer.bid_projections WHERE stream=$1 AND courier=$2',[stream,f.other]);
  assert.ok((await resumed.reconcile()).mismatches>0);await resumed.replay();assert.equal((await resumed.reconcile()).mismatches,0);await resumed.once();
  // Fresh event scan also catches an RPC omission without modifying the durable inbox.
  const original=f.logs.get(101n);f.logs.set(101n,original.filter(log=>log.logIndex!==2));
  assert.ok((await resumed.reconcile()).mismatches>0);f.logs.set(101n,original);
  assert.equal((await resumed.reconcile()).mismatches,0);await resumed.once();
  let release;let entered;
  const held=new Promise(resolve=>{release=resolve;});const started=new Promise(resolve=>{entered=resolve;});
  const heldRpc=Object.create(rpc);heldRpc.block=async number=>{entered();await held;return rpc.block(number);};
  const running=new IndexerWorker(pool,heldRpc,f.bundle,f.settings).once();await started;
  try{await assert.rejects(resumed.once(),/Indexer operation failed/);}finally{release();}
  await running;assert.equal((await reads.read('status')).indexing.status,'ready');
  const beforeReplay=(await reads.read('delivery','0')).data;
  await pool.query(`UPDATE monosfer.delivery_projections SET data=jsonb_set(data,'{state}','"Bidding"') WHERE stream=$1`,[stream]);
  assert.ok((await resumed.reconcile()).mismatches>=1);assert.equal(await resolver.findConfirmed(privateId),null);
  await assert.rejects(resumed.once(),/Indexer operation failed/);
  await resumed.replay();assert.deepEqual((await reads.read('delivery','0')).data,beforeReplay);
  assert.equal((await reads.read('status')).indexing.status,'error','replay requires chain reconciliation before serving ready');
  assert.equal((await resumed.reconcile()).mismatches,0);await resumed.once();
  f.head=105n;await resumed.once();await resumed.once();assert.equal((await reads.read('delivery','0')).data.state,'Completed');
  assert.equal((await resumed.reconcile()).mismatches,0);await resumed.once();
  // Reorg starts after funding. Old success events remain as orphan inbox records.
  for(let n=103n;n<=105n;n++) {f.blocks.set(n,{number:n,hash:hashOf(`fork${n}`),parentHash:n===103n?f.blocks.get(102n).hash:hashOf(`fork${n-1n}`)});f.logs.set(n,[]);}
  f.event(103,'StateChanged',{deliveryId:0n,from:3,to:9,deadline:0n});f.event(103,'Settled',{deliveryId:0n,finalState:9});
  await resumed.once();await resumed.once();
  assert.equal((await reads.read('delivery','0')).data.state,'Cancelled');
  assert.ok((await pool.query('SELECT count(*)::int AS n FROM monosfer.chain_event_inbox WHERE stream=$1 AND NOT canonical',[stream])).rows[0].n>0);
  await assert.rejects(privateService.readDelivery(privateId,f.courier),error=>error.getStatus()===403);
  // ABI drift and wrong chain never advance the cursor.
  await assert.rejects(new IndexerWorker(pool,rpc,{...f.bundle,fingerprint:'a'.repeat(64)},f.settings).once(),/Indexer operation failed/);
  f.wrongChain=true;await assert.rejects(resumed.once(),/Indexer operation failed/);f.wrongChain=false;
  // An ancestor outside the allowed window cannot silently reset a confirmed projection.
  for(let n=99n;n<=105n;n++) f.blocks.set(n,{number:n,hash:hashOf(`deep${n}`),parentHash:hashOf(`deep${n-1n}`)});
  await assert.rejects(resumed.once(),/Indexer operation failed/);
  assert.equal((await reads.read('delivery','0')).data.state,'Cancelled');assert.equal((await reads.read('status')).indexing.status,'error');
  assert.equal(await resolver.findConfirmed(privateId),null);
  for(const secret of ['PRIVATE_ADDRESS','PRIVATE_CODE','RPC_PRIVATE_SECRET']) assert.equal(logs.join('').includes(secret),false);
  assert.equal(f.requests.some(method=>/send|sign/i.test(method)),false);
});
