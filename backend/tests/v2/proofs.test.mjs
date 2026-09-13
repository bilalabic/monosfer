import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { generatePrivateKey, privateKeyToAccount } from 'viem/accounts';
import { recoverTypedDataAddress, keccak256, stringToHex } from 'viem';
import { ConfigService, parseSettings } from '../../dist/config/config.js';
import { proofTypedData, acceptanceTypes, attestationTypes } from '../../dist/proofs/typed-data.js';
import { parseProofSettings } from '../../dist/proofs/config.js';
import { verifyDeliveryCode } from '../../dist/proofs/proofs.service.js';
import { ProofsService } from '../../dist/proofs/proofs.service.js';
import { states, decodeLogs, reduceEvent } from '../../dist/indexer/events.js';
import { reduceDispute } from '../../dist/indexer/disputes.js';
import { HubRpc } from '../../dist/indexer/rpc.js';
import { testEnv, testApplication } from '../support/app.mjs';
import { hubFixture, rpcServer, hashOf } from '../support/indexer.mjs';
import { memoryStores, login, wallet, origin } from '../support/auth.mjs';
import { proofRpc, solidityProofHash } from '../support/proofs.mjs';

test('state offsets, timestamps, disputed/resolved transitions and ABI proof field order',()=>{
  assert.deepEqual(states,['None','Bidding','AwaitingFunding','ReadyForPickup','InTransit','DeliveredPending','ReturnRequired','Disputed','Completed','Returned','Resolved','Cancelled','Expired']);
  const source=readFileSync(new URL('../../../contracts/src/v1/hub/DeliveryHub.sol',import.meta.url),'utf8');
  assert.deepEqual(source.match(/enum State\s*\{([^}]+)\}/)[1].replace(/\/\/[^\n]*/g,'').split(',').map(x=>x.trim()).filter(Boolean),states);
  const f=hubFixture(),p={delivery:null,bids:{}};
  for(const e of decodeLogs(f.bundle.abi,f.address,[...f.blocks.values()],[...f.logs.values()].flat()))reduceEvent(p,e);
  assert.equal(p.delivery.etaMinutes,'10');assert.equal(p.delivery.etaDeadline,'703');assert.equal(p.delivery.completedAt,'105');
  for(const from of [4,5,6]){
    const copy=structuredClone(p);copy.delivery.state=states[from];
    reduceEvent(copy,{name:'StateChanged',args:{deliveryId:'0',from:String(from),to:'7',deadline:'3000'},log:{}});
    assert.equal(copy.delivery.state,'Disputed');
    reduceEvent(copy,{name:'StateChanged',args:{deliveryId:'0',from:'7',to:'10',deadline:'0'},log:{}});assert.equal(copy.delivery.state,'Resolved');
    assert.throws(()=>reduceEvent(copy,{name:'StateChanged',args:{deliveryId:'0',from:'10',to:'8',deadline:'0'},log:{}}));
  }
  for(const [name,fields] of [['hashPickupAcceptance',acceptanceTypes.PickupAcceptance],['hashPodAttestation',attestationTypes.PodAttestation]]) {
    assert.deepEqual(f.bundle.abi.find(x=>x.name===name).inputs[0].components.map(({name,type})=>({name,type})),fields);
  }
});
test('RPC read error contains no upstream cause or credential',async t=>{
  const f=hubFixture(),server=await rpcServer(f);t.after(server.close);
  f.deliveryAt=()=>{throw new Error('PRIVATE');};
  await assert.rejects(new HubRpc(server.url).read(f.address,f.bundle.abi,'deliveryOf',[0n],102n),e=>e.message==='RPC read failed'&&!e.cause&&!String(e.stack).includes('PRIVATE'));
});
test('proof typed data matches independent Solidity hashing and binds all fields/domain',async()=>{
  const account=privateKeyToAccount(generatePrivateKey());const hub=wallet().address;
  for(const kind of ['pickup','return','pod']){
    const message={deliveryId:'1',courier:account.address,nonce:'45',expiresAt:'2000',...(kind==='pod'?{proofType:hashOf('otp'),challengeHash:hashOf('challenge'),issuedAt:'1700'}:{action:keccak256(stringToHex(kind==='pickup'?'MONOSFER.PICKUP':'MONOSFER.RETURN'))})};
    const result=proofTypedData(kind,message,10143,hub);
    assert.equal(result.digest,solidityProofHash(kind,message,10143,hub));
    const signature=await account.signTypedData(result.typedData);
    assert.equal((await recoverTypedDataAddress({...result.typedData,signature})).toLowerCase(),account.address.toLowerCase());
    for(const [key,value] of Object.entries(message)) {
      const altered=key==='courier'?wallet().address:key==='action'||key==='proofType'||key==='challengeHash'?hashOf(value):String(BigInt(value)+1n);
      assert.notEqual(proofTypedData(kind,{...message,[key]:altered},10143,hub).digest,result.digest);
    }
    assert.notEqual(proofTypedData(kind,message,1,hub).digest,result.digest);
    assert.notEqual(proofTypedData(kind,message,10143,wallet().address).digest,result.digest);
  }
});
test('proof chain verifies RPC digest, domain, nonce, signer, state, validity and freshness',async t=>{
  const hub=hubFixture(),config=new ConfigService({...parseSettings(testEnv),indexer:hub.settings});
  const rpc=await proofRpc(config,hub.customer,hub.courier);t.after(rpc.close);
  const f=rpc.fixture;const data={state:'ReadyForPickup',customer:hub.customer,courier:hub.courier};
  const snapshot=()=>rpc.chain.snapshot('pickup','0',data,'102',f.hash);
  const good=await snapshot();const message={deliveryId:'0',courier:hub.courier,action:good.action,nonce:'10',expiresAt:String(good.timestamp+100n)};
  assert.ok((await rpc.chain.finish('pickup',message,good,hub.customer)).digest);
  for(const [key,value] of [['badDomain',true],['chainId',1],['stale',true],['state',4],['fail',true]]){const old=f[key];f[key]=value;await assert.rejects(snapshot,e=>e.getStatus()===503);f[key]=old;}
  for(const key of ['used','badHash']){f[key]=true;await assert.rejects(rpc.chain.finish('pickup',message,good,hub.customer));f[key]=false;}
  f.state=4;const pod=()=>rpc.chain.snapshot('pod','0',{...data,state:'InTransit'},'102',f.hash);
  assert.ok((await pod()).signer);
  for(const [key,value] of [['badSigner',true],['validity',1]]){const old=f[key];f[key]=value;await assert.rejects(pod);f[key]=old;}
  config.settings.proofs.signerPrivateKey=undefined;await assert.rejects(pod);
  assert.equal(f.requests.some(x=>/send|sign/i.test(x)),false);
});
test('proof input, config, CSRF, auth and logs fail closed',async t=>{
  assert.doesNotThrow(()=>verifyDeliveryCode('test-code','test-code'));
  for(const value of [undefined,'','other'])assert.throws(()=>verifyDeliveryCode(value,'test-code'));
  for(const env of [{POD_ATTESTATION_TTL_SECONDS:'601'},{PROOF_ACCEPTANCE_TTL_SECONDS:'0'},{POD_ATTESTATION_SIGNER_PRIVATE_KEY:'PRIVATE'}])assert.throws(()=>parseProofSettings(env));
  const stores=memoryStores();const {app,logs,logger}=await testApplication({...stores,redis:stores.redis,providers:[[ProofsService,{issue:async()=>({status:'issued'})}]]});t.after(()=>app.close());
  const session=await login(app,wallet());const url='/v1/deliveries/0/pod-attestations';
  assert.equal((await app.inject({method:'POST',url,payload:{}})).statusCode,401);
  assert.equal((await app.inject({method:'POST',url,headers:{origin,cookie:session.cookie},payload:{}})).statusCode,403);
  const headers={origin,cookie:session.cookie,'x-csrf-token':session.csrfToken};
  for(const payload of [{proofType:'recipient_signature',code:'secret'},{proofType:'otp',code:'secret',extra:'PRIVATE'},{proofType:'otp',code:''}])assert.equal((await app.inject({method:'POST',url,headers,payload})).statusCode,400);
  assert.equal((await app.inject({method:'POST',url:'/v1/deliveries/0/pickup-acceptances',headers,payload:{extra:'PRIVATE'}})).statusCode,400);
  logger.info({code:'PRIVATE_CODE',otp:'PRIVATE_OTP',POD_ATTESTATION_SIGNER_PRIVATE_KEY:'PRIVATE_KEY',attestation:{signature:'PRIVATE_SIGNATURE'}});
  for(const value of ['PRIVATE_CODE','PRIVATE_OTP','PRIVATE_KEY','PRIVATE_SIGNATURE'])assert.equal(logs.join('').includes(JSON.stringify(value)),false,value);
});
test('dispute reducer distinguishes committee resolution, settlement and abandonment',()=>{
  const event=(name,args={})=>({name,args:{disputeId:'0',...args}});
  let d=reduceDispute(null,event('DisputeOpened',{deliveryId:'4',opener:wallet().address}));
  for(const [name,args] of [['EvidenceSubmitted',{}],['PanelSeated',{round:'0'}],['Appealed',{round:'1'}],['ResolvedByCommittee',{round:'1',ruling:'2'}],['DisputeSettled',{customerBps:'10000',ruling:'2'}]])d=reduceDispute(d,event(name,args));
  assert.equal(d.status,'settled');assert.equal(d.committeeResolutionAlert,true);assert.equal(d.evidenceCount,1);
  assert.throws(()=>reduceDispute(d,event('DisputeOpened',{deliveryId:'4',opener:wallet().address})));
  assert.throws(()=>reduceDispute(null,event('EvidenceSubmitted')));
});
