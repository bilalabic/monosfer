import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { verifyTypedData } from 'viem';
import { ConfigService } from '../../dist/config/config.js';
import { QuoteChain, QuoteSigner } from '../../dist/quotes/chain.js';
import { QuotesService } from '../../dist/quotes/quotes.service.js';
import { QuotesRepository } from '../../dist/quotes/quotes.repository.js';
import { QuoteLinkWorker } from '../../dist/quotes/link-worker.js';
import { DeterministicRiskAdapter } from '../../dist/quotes/risk.js';
import { typedQuote, amount } from '../../dist/quotes/typed-data.js';
import { parseQuoteSettings } from '../../dist/quotes/config.js';
import { idempotencyScope, privateHash } from '../../dist/quotes/idempotency.js';
import { quoteFixture, quoteRpcServer, solidityHashQuote, quoteInput } from '../support/quotes.mjs';
import { authApplication, login, origin } from '../support/auth.mjs';

const quoteFor=f=>({customer:f.account.address,riskTier:1,declaredValue:'10000',requiredCoverage:'3750',issuedAt:'1800000000',expiresAt:'1800000300',salt:`0x${'ab'.repeat(32)}`});
test('EIP-712 matches independent Solidity encoding and exported ABI; signature binds all fields and domain',async t=>{
  const f=quoteFixture();const rpc=await quoteRpcServer(f);t.after(()=>rpc.close());
  const q=quoteFor(f);const snapshot=await f.chain.snapshot();
  const signed=await new QuoteSigner(f.config,f.chain).sign(q,snapshot);
  assert.equal(signed.quoteDigest,solidityHashQuote(q,10143,f.hub.address));
  assert.deepEqual(Object.keys(q),['customer','riskTier','declaredValue','requiredCoverage','issuedAt','expiresAt','salt']);
  assert.ok(await verifyTypedData({...signed.typedData,signature:signed.signature,address:f.signer.address}));
  assert.equal(await verifyTypedData({...signed.typedData,signature:signed.signature,address:f.account.address}),false);
  for(const changes of [{customer:f.signer.address},{riskTier:2},{declaredValue:'10001'},{requiredCoverage:'3751'},
    {issuedAt:'1800000001'},{expiresAt:'1800000299'},{salt:`0x${'cd'.repeat(32)}`}]){
    assert.equal(await verifyTypedData({...signed.typedData,message:{...q,...changes},signature:signed.signature,address:f.signer.address}),false);
  }
  for(const domain of [{...signed.typedData.domain,chainId:1},{...signed.typedData.domain,verifyingContract:f.account.address}]){
    assert.equal(await verifyTypedData({...signed.typedData,domain,signature:signed.signature,address:f.signer.address}),false);
  }
  assert.equal(f.requests.some(name=>/send|sign/i.test(name)),false);
});
test('uint96/uint64, tier, expiry and coverage boundaries reject malformed input',async()=>{
  const f=quoteFixture();const q=quoteFor(f);
  assert.equal(amount(String(2n**96n-1n)),2n**96n-1n);
  for(const changes of [{declaredValue:'0'},{declaredValue:String(2n**96n)},{declaredValue:'1.1'},{declaredValue:'01'},
    {requiredCoverage:'0'},{riskTier:0},{riskTier:4},{riskTier:1.5},{issuedAt:String(2n**64n)},
    {expiresAt:q.issuedAt},{expiresAt:'1800000301'}])assert.throws(()=>typedQuote({...q,...changes},10143,f.hub.address,300),e=>e.getStatus()===400);
  const adapter=new DeterministicRiskAdapter();const p={validity:300,coverageBps:5000n,minBps:7500n,maxBps:15000n};
  assert.equal((await adapter.evaluate(quoteInput(),p)).requiredCoverage,'3750');
  await assert.rejects(adapter.evaluate({...quoteInput(),declaredValue:'1'},p),e=>e.getStatus()===503);
});
test('RPC policy fails closed on stale price context, rotation, validity, chain/config/hash and block changes',async t=>{
  const f=quoteFixture();const rpc=await quoteRpcServer(f);t.after(()=>rpc.close());
  for(const key of ['stale','badSigner','badConfig','fail']){
    f[key]=true;await assert.rejects(f.chain.snapshot(),e=>e.getStatus()===503);f[key]=false;
  }
  f.chainId=1;await assert.rejects(f.chain.snapshot(),e=>e.getStatus()===503);f.chainId=10143;
  f.validity=299;await assert.rejects(f.chain.snapshot(),e=>e.getStatus()===503);f.validity=300;
  const snapshot=await f.chain.snapshot();const signer=new QuoteSigner(f.config,f.chain);
  for(const key of ['badHash','badBlock']){
    f[key]=true;await assert.rejects(signer.sign(quoteFor(f),snapshot),e=>e.getStatus()===503);f[key]=false;
  }
  f.settings.environment='production';assert.throws(()=>f.chain.assertAvailable(),e=>e.getStatus()===503);
  f.settings.environment='test';f.settings.quotes.signerPrivateKey=undefined;assert.throws(()=>f.chain.assertAvailable(),e=>e.getStatus()===503);
});
test('quote configuration and canonical HMAC idempotency are strict and privately scoped',()=>{
  assert.equal(parseQuoteSettings({}).workerEnabled,false);
  for(const env of [{QUOTE_SIGNER_PRIVATE_KEY:'SECRET'},{QUOTE_SIGNER_PRIVATE_KEY:`0x${'0'.repeat(64)}`},{QUOTE_TTL_SECONDS:'0'},
    {QUOTE_IDEMPOTENCY_TTL_SECONDS:'299'},{QUOTE_LINK_WORKER_ENABLED:'yes'},{RISK_ADAPTER_MODE:'production'},
    {QUOTE_LINK_WORKER_ENABLED:'true',NODE_ENV:'production',INDEXER_ENABLED:'true'}])assert.throws(()=>parseQuoteSettings(env));
  const secret=Buffer.alloc(32,7).toString('base64');const key=randomUUID();
  assert.equal(privateHash({b:2,a:1},secret),privateHash({a:1,b:2},secret));
  const scope=(owner,route,stream)=>idempotencyScope(key,owner,route,stream,secret);
  assert.notEqual(scope('a','create','10143'),scope('b','create','10143'));
  assert.notEqual(scope('a','create','10143'),scope('a','refresh','10143'));
  assert.notEqual(scope('a','create','10143'),scope('a','create','1'));
  for(const bad of [undefined,'short','SECRET\n'.repeat(5),['a','b']])assert.throws(()=>idempotencyScope(bad,'a','r','s',secret));
});
test('quote worker stays opt-in and production API/worker refuse deterministic signing',async()=>{
  const f=quoteFixture();const repository=new QuotesRepository({},f.config);
  const worker=new QuoteLinkWorker(f.config,repository);
  f.settings.quotes.workerEnabled=false;await assert.rejects(worker.once(),e=>e.getStatus()===503);
  f.settings.quotes.workerEnabled=true;f.settings.environment='production';await assert.rejects(worker.once(),e=>e.getStatus()===503);
  const service=new QuotesService(f.config,repository,new DeterministicRiskAdapter(),f.chain,new QuoteSigner(f.config,f.chain));
  await assert.rejects(service.status(`0x${'a'.repeat(64)}`,f.account.address),e=>e.getStatus()===503);
});
test('Fastify quote auth/CSRF, nested validation, CORS, OpenAPI, unavailable service and redaction',async t=>{
  const {app,document,logs,logger}=await authApplication();t.after(()=>app.close());
  const session=await login(app);const payload=quoteInput();
  const headers={origin,cookie:session.cookie,'x-csrf-token':session.csrfToken,'idempotency-key':randomUUID()};
  const post=(body=payload,h=headers)=>app.inject({method:'POST',url:'/v1/quotes/delivery',headers:Object.fromEntries(Object.entries(h).filter(([,v])=>v!==undefined)),payload:body});
  assert.equal((await post(payload,{origin})).statusCode,401);
  assert.equal((await post(payload,{...headers,'x-csrf-token':undefined})).statusCode,403);
  assert.equal((await post(payload,{...headers,origin:'https://evil.example.com'})).statusCode,403);
  assert.equal((await post(payload,{...headers,'idempotency-key':undefined})).statusCode,400);
  for(const bad of [{...payload,customer:session.user.walletAddress},{...payload,declaredValue:'0'},
    {...payload,declaredValue:String(2n**96n)},{...payload,privatePayload:{...payload.privatePayload,secret:'x'}},
    {...payload,metadata:{...payload.metadata,riskTier:3}},{...payload,privatePayload:{pickup:[],dropoff:{}}},
    {...payload,privatePayload:{...payload.privatePayload,pickup:{...payload.privatePayload.pickup,lat:91}}},
    {...payload,privatePayload:{...payload.privatePayload,dropoff:{...payload.privatePayload.dropoff,deliveryCode:null}}}])assert.equal((await post(bad)).statusCode,400);
  const unavailable=await post();assert.equal(unavailable.statusCode,503);
  assert.deepEqual(Object.keys(unavailable.json().error).sort(),['code','message','requestId']);
  assert.equal((await app.inject({method:'POST',url:`/v1/quotes/0x${'a'.repeat(64)}/refresh`,headers,payload:{customer:'bad'}})).statusCode,400);
  const preflight=await app.inject({method:'OPTIONS',url:'/v1/quotes/delivery',headers:{origin,'access-control-request-method':'POST','access-control-request-headers':'content-type,x-csrf-token,idempotency-key'}});
  assert.ok(preflight.headers['access-control-allow-headers'].includes('idempotency-key'));
  assert.ok(document.paths['/v1/quotes/{quoteDigest}/refresh'].post);
  assert.equal(document.components.schemas.QuotePrivatePayloadDto.additionalProperties,false);
  logger.info({quote:{salt:'QUOTE_SALT'},typedData:{message:'QUOTE_MESSAGE'},privatePayload:payload.privatePayload,signature:'QUOTE_SIGNATURE',salt:'QUOTE_SALT',QUOTE_SIGNER_PRIVATE_KEY:'QUOTE_KEY'});
  for(const secret of ['QUOTE_PRIVATE','QUOTE_SALT','QUOTE_MESSAGE','QUOTE_SIGNATURE','QUOTE_KEY',session.csrfToken])assert.equal(logs.join('').includes(secret),false);
});
