import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { operationsFixture } from '../support/operations.mjs';
import { wallet,login } from '../support/auth.mjs';
import { AuditService } from '../../dist/audit/audit.module.js';
import { ProviderWorker } from '../../dist/providers/worker.js';
import { ReputationService } from '../../dist/reputation/reputation.service.js';
import { OpsService } from '../../dist/ops/ops.service.js';
import { ConfigService } from '../../dist/config/config.js';
import { IndexerReadRepository } from '../../dist/indexer/read.module.js';

test('phase 7 real SQL/Redis: case/audit atomicity, trusted access, reputation rebuild and telemetry',{timeout:60000},async t=>{
  const f=await operationsFixture(t),admin=wallet(),support=wallet();
  const release={...f.settings.release,supportEnabled:true,adminWallets:[admin.address.toLowerCase()],supportWallets:[support.address.toLowerCase()],metricsToken:'test-only-ops-token-'.repeat(3),traceSampleRate:1};
  const settings={...f.settings,release};
  const api=await f.makeApp({settings});
  const identities={...f.sessions,admin:await login(api.app,admin),support:await login(api.app,support)};
  const headers=(who,extra={})=>({origin:'https://app.example.com',cookie:identities[who].cookie,'x-csrf-token':identities[who].csrfToken,...extra});
  const get=(who,path)=>api.app.inject({url:path,headers:headers(who)});
  const post=(who,payload,key=randomUUID())=>api.app.inject({method:'POST',url:'/v1/support/cases',headers:headers(who,{'idempotency-key':key}),payload});
  const patch=(who,id,payload)=>api.app.inject({method:'PATCH',url:`/v1/support/cases/${id}`,headers:headers(who),payload});
  const counts=async()=>({cases:(await f.db.query('SELECT count(*)::int AS n FROM monosfer.support_cases WHERE stream=$1',[f.stream])).rows[0].n,
    events:(await f.db.query('SELECT count(*)::int AS n FROM monosfer.support_case_events e JOIN monosfer.support_cases c ON c.id=e.case_id WHERE c.stream=$1',[f.stream])).rows[0].n});
  let caseId,evidenceId;
  await t.test('SIWE allowlist, CSRF, DTO and standard errors reject unauthorized requests',async()=>{
    assert.equal((await get('customer','/v1/support/cases')).statusCode,403);
    assert.equal((await api.app.inject('/v1/support/cases')).statusCode,401);
    assert.equal((await get('support','/v1/admin/audit')).statusCode,403);
    assert.equal((await api.app.inject({method:'POST',url:'/v1/support/cases',headers:{cookie:identities.support.cookie,origin:'https://app.example.com'},payload:{id:'0'}})).statusCode,403);
    assert.equal((await post('support',{id:'0',email:'PRIVATE_EMAIL'})).statusCode,400);
    assert.equal((await post('support',{id:'0',note:null})).statusCode,400);
    assert.equal((await post('support',{id:'0',assignee:f.other.address})).statusCode,400);
    assert.equal((await api.app.inject({method:'POST',url:'/v1/support/cases',headers:headers('support'),payload:{id:'0'}})).statusCode,400);
  });
  await t.test('case create serializes concurrent idempotency, encrypts notes, commits audit with transition',async()=>{
    const key=randomUUID(),input={id:'0',assignee:support.address,note:'PRIVATE_SUPPORT_NOTE'};
    const responses=await Promise.all([post('support',input,key),post('support',input,key)]);
    assert.deepEqual(responses.map(r=>r.statusCode),[201,201]);assert.deepEqual(responses[0].json(),responses[1].json());caseId=responses[0].json().id;
    assert.deepEqual(await counts(),{cases:1,events:1});
    assert.equal((await post('support',{...input,note:'CHANGED'},key)).statusCode,409);
    assert.equal((await patch('support',caseId,{status:'investigating'})).statusCode,200);
    assert.deepEqual((await post('support',input,key)).json(),responses[0].json(),'idempotency replays original response after PATCH');
    assert.equal((await patch('support',caseId,{status:'open'})).statusCode,200);
    const stored=(await f.db.query('SELECT encrypted_note FROM monosfer.support_cases WHERE id=$1',[caseId])).rows[0].encrypted_note;
    assert.equal(JSON.stringify(stored).includes(input.note),false);
    const detail=await get('support',`/v1/support/cases/${caseId}`);assert.equal(detail.statusCode,200);assert.equal(detail.body.includes(input.note),false);
    const audited=(await f.db.query('SELECT decision FROM monosfer.privileged_audit_log WHERE request_id=$1',[responses[0].headers['x-request-id']])).rows;
    assert.deepEqual(audited,[{decision:'allowed'}]);
  });
  await t.test('audit insertion failure rolls back case and event; private reads do not escape',async()=>{
    const audit=api.app.get(AuditService),append=audit.append.bind(audit),before=await counts();
    audit.append=async(...args)=>{if(args[1]==='allowed')throw new Error('PRIVATE_AUDIT_FAILURE');return append(...args);};
    try {
      const create=await post('admin',{id:'1'});assert.equal(create.statusCode,503);assert.equal(create.body.includes('PRIVATE_AUDIT_FAILURE'),false);
      assert.deepEqual(await counts(),before);
      assert.equal((await get('admin','/v1/support/deliveries/0/private')).statusCode,503);
      const update=await patch('admin',caseId,{status:'closed'});assert.equal(update.statusCode,503);
      assert.equal((await f.db.query('SELECT status FROM monosfer.support_cases WHERE id=$1',[caseId])).rows[0].status,'open');
    } finally {audit.append=append;}
  });
  await t.test('private fields require assigned open case; admin bypass is explicit; code excluded',async()=>{
    assert.equal((await get('support','/v1/support/deliveries/1/private')).statusCode,403);
    const allowed=await get('support','/v1/support/deliveries/0/private');assert.equal(allowed.statusCode,200);assert.equal(allowed.json().pickup.address,'OPS_PRIVATE_PICKUP');
    assert.equal(allowed.body.includes('OPS_PRIVATE_CODE'),false);
    assert.equal((await get('admin','/v1/support/deliveries/1/private')).statusCode,200);
    assert.equal((await patch('support',caseId,{status:'closed'})).statusCode,200);
    assert.equal((await get('support','/v1/support/deliveries/0/private')).statusCode,403);
    assert.equal((await patch('admin',caseId,{status:'investigating'})).statusCode,200);
    assert.equal((await get('support','/v1/support/deliveries/0/private')).statusCode,200);
    assert.equal((await patch('admin',caseId,{assignee:null})).statusCode,200);
    assert.equal((await get('support','/v1/support/deliveries/0/private')).statusCode,403);
    assert.equal((await patch('admin',caseId,{assignee:support.address})).statusCode,200);
  });
  await t.test('stale/integrity/fingerprint/lag and missing link fail closed',async()=>{
    for(const fragment of ["status='error'","integrity_ok=false","export_fingerprint=repeat('0',64)","checked_at=now()-interval '2 hours'","observed_head=last_block+1"]){
      await f.db.query(`UPDATE monosfer.indexer_streams SET ${fragment} WHERE stream=$1`,[f.stream]);
      assert.equal((await get('admin','/v1/support/deliveries/0/private')).statusCode,503);
      await f.db.query("UPDATE monosfer.indexer_streams SET status='ready',integrity_ok=true,export_fingerprint=$2,checked_at=now(),observed_head=last_block WHERE stream=$1",[f.stream,f.settings.indexer.fingerprint]);
    }
    const record=f.recordIds[0];
    const old=(await f.db.query('SELECT quote_digest FROM monosfer.private_delivery_links WHERE private_record_id=$1',[record])).rows[0].quote_digest;
    await f.db.query("UPDATE monosfer.private_delivery_links SET quote_digest='0x'||repeat('0',64) WHERE private_record_id=$1",[record]);
    assert.equal((await get('admin','/v1/support/deliveries/0/private')).statusCode,403);
    await f.db.query('UPDATE monosfer.private_delivery_links SET quote_digest=$2 WHERE private_record_id=$1',[record,old]);
    assert.equal((await get('admin','/v1/support/deliveries/999/private')).statusCode,403);
  });
  await t.test('case-assigned support evidence read is bound, audited and revoked on closure',async()=>{
    const created=await f.app.inject({method:'POST',url:'/v1/deliveries/0/evidence',headers:f.headers('courier',{'idempotency-key':randomUUID()}),payload:{contentType:'text/plain',text:'PRIVATE_SUPPORT_EVIDENCE'}});
    assert.equal(created.statusCode,201);evidenceId=created.json().evidenceId;
    await f.app.get(ProviderWorker).once();
    const path=`/v1/support/deliveries/0/evidence/${evidenceId}/content`;
    const content=await get('support',path);assert.equal(content.statusCode,200);assert.equal(content.json().text,'PRIVATE_SUPPORT_EVIDENCE');
    assert.equal((await get('admin',`/v1/support/deliveries/1/evidence/${evidenceId}/content`)).statusCode,404);
    await patch('support',caseId,{status:'closed'});assert.equal((await get('support',path)).statusCode,403);
    assert.equal((await get('admin',path)).statusCode,200);
    const metadata=await get('support','/v1/support/deliveries/0/evidence');assert.equal(metadata.statusCode,200);assert.equal(metadata.body.includes('PRIVATE_SUPPORT_EVIDENCE'),false);
    const audit=(await f.db.query('SELECT action,decision FROM monosfer.privileged_audit_log WHERE request_id=$1',[content.headers['x-request-id']])).rows[0];assert.deepEqual(audit,{action:'support.content',decision:'allowed'});
    const checksum=(await f.db.query('SELECT ciphertext_hash FROM monosfer.evidence_packages WHERE id=$1',[evidenceId])).rows[0].ciphertext_hash;
    await f.db.query("UPDATE monosfer.evidence_packages SET ciphertext_hash=repeat('0',64) WHERE id=$1",[evidenceId]);
    assert.equal((await get('admin',path)).statusCode,503);
    await f.db.query('UPDATE monosfer.evidence_packages SET ciphertext_hash=$2 WHERE id=$1',[evidenceId,checksum]);
  });
  await t.test('audit/event records are append-only at SQL layer',async()=>{
    for(const statement of ["UPDATE monosfer.privileged_audit_log SET decision='allowed' WHERE false",'DELETE FROM monosfer.privileged_audit_log WHERE false',
      'TRUNCATE monosfer.privileged_audit_log',"UPDATE monosfer.support_case_events SET status='closed' WHERE false",'DELETE FROM monosfer.support_case_events WHERE false'])await assert.rejects(f.db.query(statement),/Append-only/);
    const page=await get('admin','/v1/admin/audit?limit=1');assert.equal(page.statusCode,200);assert.equal(page.json().data.length,1);assert.ok(page.json().nextCursor);
  });
  await t.test('dry-run writes nothing; repeat rebuild stable; changed stream invalidates old counters',async()=>{
    const reputation=api.app.get(ReputationService);
    const count=async()=>(await f.db.query('SELECT count(*)::int AS n FROM monosfer.reputation_projections WHERE stream=$1',[f.stream])).rows[0].n;
    assert.equal((await reputation.rebuild(false)).mode,'dry-run');assert.equal(await count(),0);
    await f.db.query("UPDATE monosfer.delivery_projections SET data=jsonb_set(data,'{state}','\"Completed\"') WHERE stream=$1 AND delivery_id=0",[f.stream]);
    await reputation.rebuild(true);const first=await reputation.read(f.customer.address);assert.equal(first.status,'ready');assert.equal(first.counters.customerCompleted,'1');assert.equal(first.reward.status,'pending_policy');
    await reputation.rebuild(true);const second=await reputation.read(f.customer.address);assert.deepEqual(first.counters,second.counters);assert.equal(await count(),2);
    const response=await get('customer','/v1/users/me/reputation');assert.equal(response.statusCode,200);
    assert.equal(response.json().source,'backend_delivery_projection');assert.equal(response.json().onChainReputation.status,'export_missing');
    const summary=await get('support','/v1/support/deliveries/0');assert.equal(summary.statusCode,200);
    assert.equal(summary.json().dispute,null);assert.equal(summary.json().committeeResolutionAlert,false);
    assert.equal((await get('support',`/v1/support/wallets/${f.customer.address}/reputation`)).statusCode,200);
    await f.db.query("UPDATE monosfer.indexer_streams SET last_hash='0x'||repeat('1',64) WHERE stream=$1",[f.stream]);
    assert.equal((await reputation.read(f.customer.address)).status,'rebuild_pending');
    await f.db.query("UPDATE monosfer.indexer_streams SET integrity_ok=false WHERE stream=$1",[f.stream]);
    await assert.rejects(reputation.rebuild(true),e=>e.getStatus()===503);
    await f.db.query('UPDATE monosfer.indexer_streams SET integrity_ok=true WHERE stream=$1',[f.stream]);
    // Only derived fixture rows; audit and case history intentionally survive fixture cleanup.
    await f.db.query('DELETE FROM monosfer.referral_reward_projections WHERE stream=$1',[f.stream]);
    await f.db.query('DELETE FROM monosfer.reputation_projections WHERE stream=$1',[f.stream]);
  });
  await t.test('ops token, admin trace fallback, sampled privacy and dependency failure reporting',async()=>{
    assert.equal((await get('admin','/v1/ops/status')).statusCode,401);
    const tokenHeaders={authorization:`Bearer ${release.metricsToken}`};
    const status=await api.app.inject({url:'/v1/ops/status',headers:tokenHeaders});assert.equal(status.statusCode,200);assert.equal(status.json().postgres,true);
    const requestId=status.headers['x-request-id'];
    // onResponse telemetry is committed after the response is sent; read-your-trace is eventually consistent.
    let traces;
    for(let attempt=0;attempt<20;attempt++){
      traces=await api.app.inject({url:`/v1/ops/traces/${requestId}`,headers:tokenHeaders});
      if(traces.json().data?.length)break;await delay(10);
    }
    assert.equal(traces.statusCode,200);assert.equal(traces.json().data.length,1);
    assert.equal((await get('admin',`/v1/ops/traces/${requestId}`)).statusCode,200);
    assert.equal((await get('support',`/v1/ops/traces/${requestId}`)).statusCode,403);
    const config=new ConfigService(settings),indexer=new IndexerReadRepository(f.db,config);
    const outage=await new OpsService(f.db,{ping:async()=>false},config,indexer).status();assert.equal(outage.redis,false);assert.equal(outage.status,'degraded');
    const pgOutage=await new OpsService({ping:async()=>false},f.redis,config,indexer).status();assert.equal(pgOutage.postgres,false);
    const all=JSON.stringify((await f.db.query('SELECT * FROM monosfer.ops_trace_events WHERE request_id=$1',[requestId])).rows);
    for(const secret of [release.metricsToken,'PRIVATE_SUPPORT_NOTE','PRIVATE_SUPPORT_EVIDENCE','OPS_PRIVATE_CODE'])assert.equal(all.includes(secret),false);
  });
  for(const secret of ['PRIVATE_SUPPORT_NOTE','PRIVATE_SUPPORT_EVIDENCE','OPS_PRIVATE_PICKUP','OPS_PRIVATE_CODE','PRIVATE_AUDIT_FAILURE'])assert.equal(api.logs.join('').includes(secret),false);
});
