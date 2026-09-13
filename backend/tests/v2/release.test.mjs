import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { unlink } from 'node:fs/promises';
import { join } from 'node:path';
import { parseReleaseSettings } from '../../dist/ops/config.js';
import { validOpsToken } from '../../dist/ops/ops.module.js';
import { AuditService, safeTarget } from '../../dist/audit/audit.module.js';
import { DevelopmentRouteProvider, InAppNotificationProvider, LocalEvidenceStorage, bounded } from '../../dist/providers/adapters.js';
import { authApplication, wallet, login, origin } from '../support/auth.mjs';
import { requireLocalOperations } from '../../dist/reputation/reputation.service.js';
import { testnetSmoke } from '../../dist/ops/testnet-smoke.js';

test('release config is opt-in; malformed secrets/wallets/limits fail without echoing data',()=>{
  assert.equal(parseReleaseSettings({}).supportEnabled,false);
  for(const env of [{SUPPORT_ENABLED:'true'},{SUPPORT_ENABLED:'yes'},{SUPPORT_WALLETS:'private-value'},
    {ADMIN_WALLETS:`0x${'0'.repeat(40)}`},{OPS_METRICS_TOKEN:'short'},{OPS_TRACE_SAMPLE_RATE:'NaN'},
    {OPS_TRACE_SAMPLE_RATE:'1.1'},{OPS_RESTORE_DRILL_TARGET_SECONDS:'0'},{SUPPORT_CASE_IDEMPOTENCY_TTL_SECONDS:'-1'},
    {TESTNET_SMOKE_RPC_URL:'file:///secret'}])assert.throws(()=>parseReleaseSettings(env));
  const account=wallet();assert.deepEqual(parseReleaseSettings({SUPPORT_ENABLED:'true',ADMIN_WALLETS:account.address}).adminWallets,[account.address.toLowerCase()]);
  for(const value of [undefined,'Bearer short',`Bearer ${'x'.repeat(400)}`,['Bearer token']])assert.equal(validOpsToken(value,'a'.repeat(32)),false);
  assert.equal(validOpsToken(`Bearer ${'a'.repeat(32)}`,'a'.repeat(32)),true);
  assert.equal(validOpsToken('Bearer ',''),false);
  assert.equal(safeTarget('PRIVATE_PHONE_AND_ADDRESS'),'invalid');
  assert.throws(()=>requireLocalOperations({environment:'production',databaseUrl:'postgresql://localhost/monosfer_v2'}));
  assert.throws(()=>requireLocalOperations({environment:'test',databaseUrl:'postgresql://remote/test'}));
});

test('support guard uses SIWE allowlist, never profile role, and audits auth/CSRF failures',async t=>{
  const admin=wallet(),support=wallet(),other=wallet(),audits=[];
  const database={ping:async()=>true,query:async(sql,args)=>{if(sql.includes('privileged_audit_log'))audits.push(args);return {rows:[]};},transaction:async work=>work(database)};
  const f=await authApplication({database,env:{SUPPORT_ENABLED:'true',ADMIN_WALLETS:admin.address,SUPPORT_WALLETS:support.address}});t.after(()=>f.app.close());
  const sessions={};for(const [key,value]of Object.entries({admin,support,other}))sessions[key]=await login(f.app,value);
  const request=(name,url='/v1/support/cases',extra={})=>f.app.inject({url,headers:{cookie:sessions[name].cookie},...extra});
  const user=f.users.get(sessions.other.user.id);user.role='admin';
  assert.equal((await request('other')).statusCode,403);
  assert.equal((await f.app.inject('/v1/support/cases')).statusCode,401);
  assert.equal((await request('support')).statusCode,200);
  assert.equal((await request('support','/v1/admin/audit')).statusCode,403);
  assert.equal((await request('admin','/v1/admin/audit')).statusCode,200);
  const csrf=await request('support','/v1/support/cases',{method:'POST',headers:{cookie:sessions.support.cookie,origin},payload:{id:'0'}});
  assert.equal(csrf.statusCode,403);assert.equal(csrf.json().error.code,'FORBIDDEN');
  const invalid=await request('support','/v1/support/cases',{method:'POST',headers:{cookie:sessions.support.cookie,origin,'x-csrf-token':sessions.support.csrfToken},payload:{id:'0',role:'admin'}});
  assert.equal(invalid.statusCode,400);
  assert.ok(audits.some(a=>a[5]==='denied'&&a[6]==='UNAUTHENTICATED'));
  assert.ok(audits.some(a=>a[1]===other.address.toLowerCase()&&a[5]==='denied'));
  assert.ok(audits.some(a=>a[5]==='allowed'));
  assert.equal((await request('support','/v1/ops/status')).statusCode,401);
  assert.equal(f.document.paths['/v1/support/cases'].post.responses[201].content['application/json'].schema.additionalProperties,false);
  assert.equal(f.document.paths['/v1/support/deliveries/{id}/private'].get.responses[200].content['application/json'].schema.properties.pickup.additionalProperties,false);
});

test('disabled support and failed audit cannot release privileged results',async t=>{
  const database={ping:async()=>true,query:async()=>({rows:[]})};
  const f=await authApplication({database});t.after(()=>f.app.close());const session=await login(f.app);
  assert.equal((await f.app.inject({url:'/v1/support/cases',headers:{cookie:session.cookie}})).statusCode,503);
  let rolledBack=false;
  const service=new AuditService({transaction:async work=>{try{return await work({query:async()=>{throw new Error('SECRET_DB');}});}catch(e){rolledBack=true;throw e;}},query:async()=>({rows:[]})});
  await assert.rejects(service.run({requestId:randomUUID(),actor:null,action:'ops.traces',targetType:'trace',targetId:randomUUID()},async()=>({private:'NEVER_RELEASE'})),e=>e.getStatus()===503);
  assert.equal(rolledBack,true);
});

test('sampled traces and ops responses contain only fixed numeric/safe fields',async t=>{
  const traces=[],database={ping:async()=>false,query:async(sql,args)=>{if(sql.includes('INSERT INTO monosfer.ops_trace_events'))traces.push(args);return {rows:[]};},transaction:async work=>work(database)};
  const token='x'.repeat(48),f=await authApplication({database,env:{OPS_METRICS_TOKEN:token,OPS_TRACE_SAMPLE_RATE:'1'}});t.after(()=>f.app.close());
  await f.app.inject({url:'/missing?email=PRIVATE_EMAIL',headers:{authorization:'Bearer PRIVATE_CREDENTIAL',cookie:'PRIVATE_COOKIE'}});
  const status=await f.app.inject({url:'/v1/ops/status',headers:{authorization:`Bearer ${token}`}});
  assert.equal(status.statusCode,200);assert.equal(status.json().postgres,false);assert.equal(status.json().status,'degraded');
  const metrics=await f.app.inject({url:'/v1/ops/metrics',headers:{authorization:`Bearer ${token}`}});
  assert.match(metrics.headers['content-type'],/^text\/plain/);assert.match(metrics.body,/monosfer_postgres_up 0/);
  const trace=await f.app.inject({url:`/v1/ops/traces/${randomUUID()}`,headers:{authorization:`Bearer ${token}`}});assert.equal(trace.statusCode,200);
  const output=JSON.stringify([traces,f.logs,status.json(),metrics.body]);
  for(const secret of ['PRIVATE_EMAIL','PRIVATE_CREDENTIAL','PRIVATE_COOKIE',token])assert.equal(output.includes(secret),false);
  assert.ok(traces.length>=3);assert.ok(traces.every(row=>row.length===3));
});

test('adapter contracts honor abort, immutable keys, retries and error redaction',async t=>{
  const signal=AbortSignal.abort(new Error('PRIVATE_PROVIDER_ERROR'));
  await assert.rejects(new DevelopmentRouteProvider().estimate({lat:0,lng:0},{lat:1,lng:1},signal));
  await assert.rejects(new InAppNotificationProvider().send('fixture',{},signal));
  const storage=new LocalEvidenceStorage(),id=randomUUID(),active=new AbortController().signal;
  t.after(async()=>{try{await unlink(join(storage.root,`${id}.json`));}catch(e){if(e.code!=='ENOENT')throw e;}});
  await assert.rejects(storage.put(id,'NEVER_WRITE',signal));
  await storage.put(id,'encrypted-fixture',active);await storage.put(id,'encrypted-fixture',active);
  assert.equal(await storage.get(id,active),'encrypted-fixture');
  await assert.rejects(storage.put(id,'DIFFERENT_PRIVATE_PAYLOAD',active));
  assert.equal(await storage.get(id,active),'encrypted-fixture');
  await assert.rejects(storage.get(id,signal));
  let aborted=false;
  await assert.rejects(bounded(10,s=>new Promise(()=>s.addEventListener('abort',()=>{aborted=true;}))),e=>e.getStatus()===503&&!e.message.includes('PRIVATE'));
  assert.equal(aborted,true);
  await assert.rejects(bounded(100,async()=>{throw new Error('PRIVATE_CREDENTIAL');}),e=>!e.message.includes('PRIVATE'));
});

test('smoke fails safely without configured RPC and never needs a signer',async()=>{
  const result=await testnetSmoke('file:///PRIVATE_SECRET');assert.equal(result.status,'failed');assert.equal(result.transactionsSent,0);
  assert.equal(JSON.stringify(result).includes('PRIVATE_SECRET'),false);
});
