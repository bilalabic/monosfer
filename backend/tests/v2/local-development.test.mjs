import test from 'node:test';
import assert from 'node:assert/strict';
import { supportsQuoteNetwork, parseQuoteSettings } from '../../dist/quotes/config.js';
import { DevelopmentDatasetService } from '../../dist/development/development.module.js';

test('local fixture signing is restricted to development and loopback chain 31337',()=>{
  assert.equal(supportsQuoteNetwork('development',31337,'http://127.0.0.1:8545'),true);
  assert.equal(supportsQuoteNetwork('test',10143,'http://127.0.0.1:8545'),true);
  for(const [environment,chain,rpc] of [['production',31337,'http://127.0.0.1:8545'],['production',10143,'https://testnet-rpc.monad.xyz'],['test',31337,'http://127.0.0.1:8545'],['development',31337,'https://rpc.example.com'],['development',31337,'http://127.0.0.1.example.com'],['development',1,'http://127.0.0.1:8545']])assert.equal(supportsQuoteNetwork(environment,chain,rpc),false);
  const env={NODE_ENV:'development',INDEXER_ENABLED:'true',INDEXER_CHAIN_ID:'31337',INDEXER_RPC_URL:'http://127.0.0.1:8545',QUOTE_LINK_WORKER_ENABLED:'true'};
  assert.equal(parseQuoteSettings(env).workerEnabled,true);
  assert.throws(()=>parseQuoteSettings({...env,NODE_ENV:'production'}));
  assert.throws(()=>parseQuoteSettings({...env,INDEXER_RPC_URL:'https://rpc.example.com'}));
});

test('fixture catalog refuses other environments before reading SQL and strips private fields',async()=>{
  const settings={environment:'development',indexer:{enabled:true,chainId:31337,rpcUrl:'http://127.0.0.1:8545',deployment:{address:`0x${'ab'.repeat(20)}`}}};
  let reads=0;
  const database={async query(sql,args){reads++;assert.equal(args[0],`31337:0x${'ab'.repeat(20)}`);return {rows:[{data:{deliveries:[{id:'1',title:'Test',phone:'PRIVATE',privateRecordId:'PRIVATE',signature:'PRIVATE'}],couriers:[{walletAddress:'0xabc',name:'Test',email:'PRIVATE',privateKey:'PRIVATE'}]}}]};}};
  const service=new DevelopmentDatasetService({settings},database);
  const result=await service.read();assert.equal(JSON.stringify(result).includes('PRIVATE'),false);assert.equal(result.deliveries[0].title,'Test');
  for(const changes of [{environment:'production'},{environment:'test'},{indexer:{...settings.indexer,chainId:10143}},{indexer:{...settings.indexer,rpcUrl:'https://rpc.example.com'}}]){
    const blocked=new DevelopmentDatasetService({settings:{...settings,...changes}},database);
    await assert.rejects(blocked.read(),error=>error.getStatus()===404);
  }
  assert.equal(reads,1);
});
