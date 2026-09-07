import test from 'node:test';
import assert from 'node:assert/strict';
import { decodeLogs, reduceEvent } from '../../dist/indexer/events.js';
import { loadBundle, parseIndexerSettings } from '../../dist/indexer/config.js';
import { HubRpc } from '../../dist/indexer/rpc.js';
import { hubFixture, rpcServer, hashOf } from '../support/indexer.mjs';
import { testApplication, testEnv } from '../support/app.mjs';
import { parseSettings } from '../../dist/config/config.js';

test('indexer config validates bounds and consumes the current nonlegacy export',()=>{
  assert.equal(parseIndexerSettings({}).enabled,false);
  const bundle=loadBundle(); assert.ok(bundle.abi.some(item=>item.type==='event'&&item.name==='DeliveryCreated'));
  assert.equal(bundle.chains[10143].legacy,undefined);
  assert.throws(()=>parseSettings({...testEnv,INDEXER_ENABLED:'true',INDEXER_RPC_URL:'https://example.com',SIWE_CHAIN_ID:'1'}),/Invalid INDEXER_CHAIN_ID/);
  for(const env of [{INDEXER_ENABLED:'yes'},{INDEXER_ENABLED:'true'},{INDEXER_ENABLED:'true',INDEXER_RPC_URL:'https://example.com',INDEXER_CHAIN_ID:'1'},
    {INDEXER_BATCH_SIZE:'201'},{INDEXER_POLL_MS:'0'},{INDEXER_REORG_DEPTH:'0'},{INDEXER_STALE_SECONDS:'1'}]) assert.throws(()=>parseIndexerSettings(env));
});
test('strict exported ABI decode orders and deduplicates without accepting conflicting or foreign logs',()=>{
  const f=hubFixture(); const blocks=[...f.blocks.values()].filter(b=>b.number>=100n&&b.number<=102n);
  const logs=[...f.logs.values()].flat().filter(l=>l.blockNumber<=102n);
  const events=decodeLogs(f.bundle.abi,f.address,blocks,[...logs].reverse().concat(logs[0]));
  assert.equal(events.length,logs.length); assert.equal(events[0].name,'DeliveryCreated');
  const p={delivery:null,bids:{}}; for(const e of events) reduceEvent(p,e);
  assert.equal(p.delivery.state,'ReadyForPickup'); assert.equal(p.delivery.returnReserve,'20'); assert.equal(p.delivery.termsVersion,'2');
  assert.equal(p.bids[f.courier].active,false); assert.equal(p.bids[f.other].active,true);
  for(const patch of [{removed:true},{address:f.customer},{blockHash:hashOf('bad')},{data:'0x01'},{topics:[hashOf('unknown')]},{logIndex:-1}]) {
    assert.throws(()=>decodeLogs(f.bundle.abi,f.address,blocks,[{...logs[0],...patch}]));
  }
  assert.throws(()=>decodeLogs(f.bundle.abi,f.address,blocks,[logs[0],{...logs[0],transactionHash:hashOf('conflict')}]));
  assert.throws(()=>reduceEvent({delivery:null,bids:{}},events.find(e=>e.name==='BidPlaced')),/Missing delivery/);
});
test('JSON-RPC adapter uses finalized/read-only methods and supports abort',async t=>{
  const f=hubFixture(); const server=await rpcServer(f);t.after(()=>server.close());
  const rpc=new HubRpc(server.url); assert.equal(await rpc.chainId(),10143);assert.equal((await rpc.block('finalized')).number,102n);
  assert.equal(await rpc.code(f.address),'0x60016001');assert.ok((await rpc.logs(f.address,100n,101n)).length>0);
  const d=await rpc.read(f.address,f.bundle.abi,'deliveryOf',[0n],102n); assert.equal(d.state,3);
  const stop=new AbortController();stop.abort();await assert.rejects(new HubRpc(server.url,stop.signal).block('finalized'));
  assert.equal(f.requests.some(method=>/send|sign/i.test(method)),false);
});
test('return, funding cancellation, expiry and losing-bid withdrawal follow contract states',()=>{
  for(const outcome of ['return','funding_cancel','expiry','withdraw']) {
    const f=hubFixture();const p={delivery:null,bids:{}};
    const end=outcome==='expiry'?100n:outcome==='funding_cancel'?101n:outcome==='return'?103n:105n;
    const base=[...f.logs.values()].flat().filter(log=>log.blockNumber<=end);
    for(const event of decodeLogs(f.bundle.abi,f.address,[...f.blocks.values()],base))reduceEvent(p,event);
    const apply=(name,args)=>reduceEvent(p,{name,args:{deliveryId:'0',...args},log:{transactionHash:hashOf(name)}});
    if(outcome==='return') {
      apply('StateChanged',{from:'4',to:'6',deadline:'2800'});apply('ReturnRequested',{by:f.customer});
      apply('StateChanged',{from:'6',to:'8',deadline:'0'});apply('Settled',{finalState:'8'});assert.equal(p.delivery.state,'Returned');
    }else if(outcome==='funding_cancel') {
      apply('StateChanged',{from:'2',to:'9',deadline:'0'});apply('Settled',{finalState:'9'});assert.equal(p.bids[f.courier].active,false);
    }else if(outcome==='expiry') {
      apply('StateChanged',{from:'1',to:'10',deadline:'0'});assert.equal(p.delivery.state,'Expired');
    }else { apply('BidWithdrawn',{courier:f.other});assert.equal(p.bids[f.other].active,false); }
    assert.throws(()=>apply('StateChanged',{from:'7',to:'1',deadline:'1'}),/Invalid lifecycle/);
  }
});
test('indexer database failures return sanitized 503',async t=>{
  const {app,logs}=await testApplication({env:{INDEXER_ENABLED:'true',INDEXER_RPC_URL:'https://example.com/SECRET_RPC'},
    database:{transaction:async()=>{throw new Error('SECRET_DB_PASSWORD');}}});t.after(()=>app.close());
  const response=await app.inject('/v1/indexer/status');assert.equal(response.statusCode,503);
  assert.equal(response.json().error.code,'SERVICE_UNAVAILABLE');assert.equal((response.body+logs.join('')).includes('SECRET_'),false);
});
test('read API validates pagination/uint256, reports pending and exposes no chain-state mutation',async t=>{
  const {app,document,logs}=await testApplication();t.after(()=>app.close());
  assert.equal((await app.inject('/v1/indexer/status')).json().status,'disabled');
  const detail=await app.inject('/v1/deliveries/0');assert.equal(detail.statusCode,202);assert.equal(detail.json().data,null);
  assert.deepEqual((await app.inject('/v1/deliveries')).json().data,[]);
  for(const url of ['/v1/deliveries?limit=101','/v1/deliveries?limit=0','/v1/deliveries?address=PRIVATE_ADDRESS','/v1/deliveries/-1',`/v1/deliveries/${2n**256n}`,'/v1/deliveries/00','/v1/deliveries/0/bids?after=not-a-wallet']) {
    const res=await app.inject(url);assert.equal(res.statusCode,400,url);assert.equal(res.json().error.code,'BAD_REQUEST');
  }
  for(const method of ['POST','PATCH','DELETE']) assert.equal((await app.inject({method,url:'/v1/deliveries/0',payload:{state:'Completed'}})).statusCode,404);
  assert.equal(logs.join('').includes('PRIVATE_ADDRESS'),false);
  const schema=document.paths['/v1/deliveries/{id}'].get.responses[200].content['application/json'].schema;
  assert.ok(schema.properties.data.properties.state.enum.includes('ReturnRequired'));
});
