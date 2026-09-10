import test from 'node:test';
import assert from 'node:assert/strict';
import { parseOperationsSettings } from '../../dist/operations/config.js';
import { DevelopmentRouteProvider, bounded, LocalEvidenceStorage } from '../../dist/providers/adapters.js';
import { authApplication, login, origin } from '../support/auth.mjs';

test('phase 6 config is opt-in, bounded and refuses production defaults',()=>{
  assert.equal(parseOperationsSettings({}).enabled,false);
  for(const env of [{OPERATIONS_ENABLED:'true'},{OPERATIONS_ENABLED:'true',INDEXER_ENABLED:'true',NODE_ENV:'production'},
    {PROVIDER_WORKER_ENABLED:'true'},{TRACKING_SESSION_TTL_SECONDS:'0'},{TRACKING_POLL_MS:'10'},
    {TRACKING_LOCATION_TTL_SECONDS:'301'},{PROVIDER_MAX_ATTEMPTS:'100'},{REALTIME_PORT:'0'},{OPERATIONS_ENABLED:'yes'}])assert.throws(()=>parseOperationsSettings(env));
  assert.equal(parseOperationsSettings({OPERATIONS_ENABLED:'true',INDEXER_ENABLED:'true',NODE_ENV:'test'}).enabled,true);
});
test('route test adapter is explicitly an estimate; provider timeout aborts work and hides raw errors',async()=>{
  const provider=new DevelopmentRouteProvider();
  const route=await provider.estimate({lat:0,lng:0},{lat:0,lng:1});
  assert.equal(route.provider,'straight-line-dev');assert.ok(route.distanceMeters>111000&&route.distanceMeters<112000);
  assert.equal((await provider.estimate({lat:0,lng:0},{lat:0,lng:0})).durationSeconds,0);
  let signal;await assert.rejects(bounded(10,s=>{signal=s;return new Promise(()=>{});}),e=>e.getStatus()===503);
  assert.equal(signal.aborted,true);
  await assert.rejects(bounded(10,async()=>{throw new Error('PROVIDER_PRIVATE_CREDENTIAL');}),e=>!e.message.includes('PRIVATE'));
  const storage=new LocalEvidenceStorage();await assert.rejects(storage.get('../../secret',new AbortController().signal),/Invalid object key/);
});
test('phase 6 HTTP validates auth/CSRF/nested DTOs; disabled providers are fail-closed and sensitive fields redact',async t=>{
  const {app,document,logger,logs}=await authApplication();t.after(()=>app.close());
  const session=await login(app);const headers={origin,cookie:session.cookie,'x-csrf-token':session.csrfToken,'idempotency-key':'phase6-test-idempotency'};
  const sample={lat:41,lng:29,sequence:1,capturedAt:new Date().toISOString()};
  const request=(url,payload,h=headers)=>app.inject({method:'POST',url,headers:h,payload});
  assert.equal((await request('/v1/deliveries/0/tracking/sessions',{},{})).statusCode,401);
  assert.equal((await request('/v1/deliveries/0/tracking/sessions',{},{origin,cookie:session.cookie})).statusCode,403);
  assert.equal((await request('/v1/deliveries/0/tracking/sessions',{})).statusCode,503);
  for(const body of [{...sample,lat:91},{...sample,sequence:0},{...sample,wallet:'foreign'},{...sample,capturedAt:'bad'}])assert.equal((await request('/v1/deliveries/0/tracking/location',body)).statusCode,400);
  for(const body of [{contentType:'text/html',text:'<script>'},{contentType:'text/plain',text:'x',gps:{lat:90,lng:0,capturedAt:new Date().toISOString(),secret:'x'}},
    {contentType:'image/png',contentBase64:'not-base64'},{contentType:'text/plain',text:'x',contentBase64:'eA=='}])assert.equal((await request('/v1/deliveries/0/evidence',body)).statusCode,400);
  assert.equal((await app.inject({url:'/v1/notifications?limit=1000',headers})).statusCode,400);
  assert.equal((await app.inject({url:'/v1/deliveries/0/route',headers})).statusCode,503);
  for(const path of ['/v1/deliveries/{id}/tracking/sessions','/v1/deliveries/{id}/evidence','/v1/deliveries/{id}/route','/v1/notifications'])assert.ok(document.paths[path]);
  assert.equal(document.paths['/v1/deliveries/{id}/tracking/events'],undefined,'SSE runs in separate app');
  assert.equal(document.components.schemas.EvidenceGpsDto.additionalProperties,false);
  logger.info({trackingSession:'PRIVATE_TRACKING_TOKEN',lat:41.123456789,lng:29.123456789,contentBase64:'PRIVATE_PHOTO',text:'PRIVATE_EVIDENCE',subscription:{endpoint:'PRIVATE_PUSH_URL'}});
  for(const secret of ['PRIVATE_TRACKING_TOKEN','41.123456789','29.123456789','PRIVATE_PHOTO','PRIVATE_EVIDENCE','PRIVATE_PUSH_URL'])assert.equal(logs.join('').includes(secret),false);
});
