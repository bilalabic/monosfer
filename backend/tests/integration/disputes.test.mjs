import test from 'node:test';
import assert from 'node:assert/strict';
import { encodeAbiParameters, encodeEventTopics } from 'viem';
import { operationsFixture } from '../support/operations.mjs';
import { hubFixture, hashOf } from '../support/indexer.mjs';
import { IndexerWorker } from '../../dist/indexer/worker.js';
import { loadBundle } from '../../dist/indexer/config.js';
import { OpsService } from '../../dist/ops/ops.service.js';
import { IndexerReadRepository } from '../../dist/indexer/read.module.js';

test('SQL finalized dispute ingest deduplicates, rebuilds and rolls committee alert back on reorg', {timeout:60000},async t=>{
  const ops=await operationsFixture(t);const f=hubFixture();const court=ops.courier.address;
  f.bundle.chains[10143].court={address:court,block:100};f.bundle.courtAbi=loadBundle().courtAbi;
  f.head=102n;const courtLogs=[];
  const emit=(height,name,args)=>{
    const event=f.bundle.courtAbi.find(e=>e.type==='event'&&e.name===name),nonIndexed=event.inputs.filter(x=>!x.indexed);
    const log={address:court,blockNumber:height,blockHash:f.blocks.get(height).hash,transactionHash:hashOf(`court:${courtLogs.length}`),
      transactionIndex:0,logIndex:courtLogs.length,topics:encodeEventTopics({abi:f.bundle.courtAbi,eventName:name,args}),data:encodeAbiParameters(nonIndexed,nonIndexed.map(x=>args[x.name]))};
    courtLogs.push(log);
  };
  emit(100n,'DisputeOpened',{disputeId:0n,deliveryId:0n,opener:f.customer});
  emit(101n,'EvidenceSubmitted',{disputeId:0n,submitter:f.customer,commitment:hashOf('evidence')});
  emit(102n,'ResolvedByCommittee',{disputeId:0n,round:0,ruling:1});
  emit(102n,'DisputeSettled',{disputeId:0n,deliveryId:0n,ruling:1,customerBps:10000,toCustomer:100n,toCourier:0n});
  const rpc={chainId:async()=>10143,code:async()=>'0x01',block:async n=>f.blocks.get(n==='finalized'?f.head:n),
    logs:async(address,from,to)=>{const logs=(address===court?courtLogs:[...f.logs.values()].flat()).filter(e=>e.blockNumber>=from&&e.blockNumber<=to);return logs.length?[...logs,logs[0]]:logs;},
    read:async(address,abi,name,args,block)=>name==='nextDeliveryId'?1n:name==='deliveryOf'?f.deliveryAt(block):f.bidAt(args[1],block)};
  // DatabaseService deliberately exposes no pool; give the worker its own scoped pg pool.
  const {Pool}=await import('pg');const pool=new Pool({connectionString:ops.settings.databaseUrl});
  const w=new IndexerWorker(pool,rpc,f.bundle,f.settings);
  t.after(async()=>{try{for(const table of ['dispute_projections','dispute_event_inbox','bid_projections','delivery_projections','chain_event_inbox','indexer_blocks','indexer_streams'])await pool.query(`DELETE FROM monosfer.${table} WHERE stream=$1`,[w.stream]);}finally{await pool.end();}});
  await w.once();await w.once();await w.once();
  const row=async()=>(await pool.query('SELECT data FROM monosfer.dispute_projections WHERE stream=$1',[w.stream])).rows[0].data;
  assert.equal((await row()).committeeResolutionAlert,true);assert.equal((await row()).evidenceCount,1);
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM monosfer.dispute_event_inbox WHERE stream=$1',[w.stream])).rows[0].n,4);
  assert.equal((await w.reconcile()).mismatches,0);await w.once();
  ops.config.settings.indexer=f.settings;
  const service=new OpsService(ops.db,ops.redis,ops.config,new IndexerReadRepository(ops.db,ops.config));
  assert.equal((await service.status()).committeeResolutions,'1');assert.match(await service.metrics(),/monosfer_committee_resolutions 1/);
  await w.replay();assert.equal((await row()).committeeResolutionAlert,true);assert.equal((await w.reconcile()).mismatches,0);await w.once();
  f.blocks.set(102n,{...f.blocks.get(102n),hash:hashOf('court-fork')});
  for(const e of f.logs.get(102n))e.blockHash=f.blocks.get(102n).hash;
  courtLogs.splice(2);
  await w.once();await w.once();
  assert.equal((await row()).committeeResolutionAlert,false);assert.equal((await row()).evidenceCount,1);
  assert.equal((await service.status()).committeeResolutions,'0');
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM monosfer.dispute_event_inbox WHERE stream=$1 AND NOT canonical',[w.stream])).rows[0].n,2);
});
