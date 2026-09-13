import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { Controller, Get, Module } from '@nestjs/common';
import { PrivateDataCrypto, parsePrivateKey, recordAad } from '../../dist/private-data/crypto.js';
import { deliveryAccess, PrivateDataService, PrivateDeliveryProjection } from '../../dist/private-data/private-data.module.js';
import { mapLegacy } from '../../dist/private-data/mapping.js';
import { parseLegacySettings } from '../../dist/private-data/legacy-source.js';
import { assertImportTarget } from '../../dist/private-data/importer.js';
import { parseSettings } from '../../dist/config/config.js';
import { testApplication, testEnv } from '../support/app.mjs';
import { authEnv } from '../support/env.mjs';
import { privateFixtures, privateSecrets } from '../support/private-data.mjs';

const crypto = new PrivateDataCrypto(parsePrivateKey(authEnv));
test('AES-GCM roundtrip, fresh IV, tamper/key/context rejection', () => {
  const payload = privateFixtures().delivery.pickup;
  const context = { id: randomUUID(), source_namespace: 'test', source_collection: 'deliveries', legacy_mongo_id: 'a'.repeat(24), kind: 'delivery', schema_version: 1 };
  const aad = recordAad(context);
  const encrypted = crypto.encrypt(payload, aad);
  assert.deepEqual(crypto.decrypt(encrypted, aad), payload);
  assert.notEqual(crypto.encrypt(payload, aad).iv, encrypted.iv);
  assert.equal(JSON.stringify(encrypted).includes('PRIVATE_ADDRESS'), false);
  for (const key of Object.keys(context)) {
    assert.throws(() => crypto.decrypt(encrypted, recordAad({ ...context, [key]: 'tampered' })), /Private data decryption failed/);
  }
  for (const [key, value] of [['alg', 'AES-128-GCM'], ['keyId', 'wrong'], ['tag', Buffer.alloc(16).toString('base64')], ['iv', Buffer.alloc(12).toString('base64')], ['ciphertext', 'invalid!'], ['aad', 'wrong']]) {
    assert.throws(() => crypto.decrypt({ ...encrypted, [key]: value }, aad), /Private data decryption failed/);
  }
  const wrongKey = new PrivateDataCrypto({ ...parsePrivateKey(authEnv), privateDataMasterKeyB64: Buffer.alloc(32, 8).toString('base64') });
  assert.throws(() => wrongKey.decrypt(encrypted, aad), /Private data decryption failed/);
  assert.throws(() => crypto.encrypt({ data: 'x'.repeat(1048576) }, aad), /Private data encryption failed/);
});

test('private config validates keys, while Mongo config is CLI-only', async t => {
  for (const value of ['', 'secret', Buffer.alloc(31).toString('base64'), Buffer.alloc(33).toString('base64'), `${authEnv.PRIVATE_DATA_MASTER_KEY_B64}\n`]) {
    assert.throws(() => parseSettings({ ...testEnv, PRIVATE_DATA_MASTER_KEY_B64: value }), { message: 'Invalid PRIVATE_DATA_MASTER_KEY_B64' });
  }
  for (const value of ['', 'bad id', '../private']) assert.throws(() => parseSettings({ ...testEnv, PRIVATE_DATA_KEY_ID: value }), /Invalid PRIVATE_DATA_KEY_ID/);
  assert.throws(() => parseLegacySettings({}), /Invalid LEGACY_MONGODB_URI/);
  const { app } = await testApplication({ env: { LEGACY_MONGODB_URI: undefined, LEGACY_MONGODB_DATABASE: undefined } });
  t.after(() => app.close());
  assert.equal((await app.inject('/v1/health/live')).statusCode, 200);
});

test('mapping encrypts private fields, preserves safe metadata and excludes legacy user email/phone', () => {
  const f = privateFixtures();
  const delivery = mapLegacy('deliveries', f.delivery);
  assert.equal(delivery.customer, f.customer);
  assert.equal(delivery.metadata.onChainRequestId, '42');
  assert.equal(delivery.payload.dropoff.deliveryCode, 'PRIVATE_CODE');
  for (const secret of privateSecrets) assert.equal(JSON.stringify(delivery.metadata).includes(secret), false);
  assert.equal(mapLegacy('disputes', f.dispute, f.delivery).parentLegacyId, f.delivery._id.toHexString());
  const user = mapLegacy('users', f.user);
  assert.deepEqual(Object.keys(user.payload).sort(), ['location', 'pushToken']);
  assert.equal(JSON.stringify(user).includes('EXCLUDED_'), false);
  assert.equal(mapLegacy('users', { _id: f.user._id, walletAddress: f.customer, email: 'EXCLUDED_EMAIL' }), null);
});

test('malformed/orphan documents are rejected with fixed reason codes only', () => {
  const f = privateFixtures();
  for (const [patch, code] of [[{ _id: 'PRIVATE_ADDRESS' }, 'INVALID_ID'], [{ customer: 'PRIVATE_PHONE' }, 'INVALID_WALLET'],
    [{ status: 'PRIVATE_CODE' }, 'INVALID_STATUS'], [{ pickup: { address: 'PRIVATE_ADDRESS', lat: 91, lng: 29 } }, 'INVALID_PAYLOAD'],
    [{ maxBudget: 'PRIVATE_PHONE' }, 'INVALID_PAYLOAD'], [{ onChainRequestId: Number.MAX_SAFE_INTEGER + 1 }, 'INVALID_PAYLOAD'],
    [{ creationTxHash: 'PRIVATE_ADDRESS' }, 'INVALID_PAYLOAD']]) {
    assert.throws(() => mapLegacy('deliveries', { ...f.delivery, ...patch }), { message: code });
  }
  assert.throws(() => mapLegacy('disputes', f.dispute, null), /MISSING_PARENT/);
  assert.throws(() => mapLegacy('disputes', { ...f.dispute, evidence: [{ type: 'unknown' }] }, f.delivery), /INVALID_PAYLOAD/);
  assert.throws(() => mapLegacy('users', { ...f.user, courierProfile: { location: { lat: 1, lng: 181 } } }), /INVALID_PAYLOAD/);
});

test('lifecycle policy denies unconfirmed, unrelated and terminal courier access', async () => {
  const f = privateFixtures(); const id = randomUUID();
  const state = { privateRecordId: id, customer: f.customer, acceptedCourier: f.courier, status: 'ReadyForPickup', verification: 'confirmed' };
  assert.equal(deliveryAccess(f.customer, id, state), 'customer');
  assert.equal(deliveryAccess(f.courier.toUpperCase().replace('0X', '0x'), id, state), 'courier');
  for (const status of ['Bidding', 'AwaitingFunding', 'DeliveredPending', 'ReturnRequired', 'Completed', 'Returned', 'Expired', 'Cancelled', 'unknown', 'Accepted']) assert.equal(deliveryAccess(f.courier, id, { ...state, status }), null);
  assert.equal(deliveryAccess(f.courier, id, { ...state, status: 'InTransit' }), 'courier');
  for (const invalid of [null, { ...state, privateRecordId: randomUUID() }, { ...state, verification: 'legacy_unverified' }]) assert.equal(deliveryAccess(f.customer, id, invalid), null);
  assert.equal(deliveryAccess(`0x${'f'.repeat(40)}`, id, state), null);
  assert.equal(await new PrivateDeliveryProjection({}, { settings: { indexer: { enabled: false } } }).findConfirmed(id), null);
});

test('service checks confirmed ownership before decrypt; courier never receives code/evidence/location', async () => {
  const f = privateFixtures(); const id = randomUUID();
  const record = { id, source_namespace: 'test', source_collection: 'deliveries', legacy_mongo_id: f.delivery._id.toHexString(), kind: 'delivery', schema_version: 1 };
  record.encrypted_payload = crypto.encrypt(mapLegacy('deliveries', f.delivery).payload, recordAad(record));
  let state = { privateRecordId: id, customer: f.customer, acceptedCourier: f.courier, status: 'ReadyForPickup', verification: 'confirmed' };
  let queries = 0;
  const service = new PrivateDataService({ find: async () => { queries++; return record; } }, crypto, { findConfirmed: async () => state });
  await assert.rejects(service.readDelivery(id, `0x${'f'.repeat(40)}`), error => error.getStatus() === 403);
  assert.equal(queries, 0);
  assert.equal((await service.readDelivery(id, f.customer)).dropoff.deliveryCode, 'PRIVATE_CODE');
  const courier = await service.readDelivery(id, f.courier);
  assert.equal(courier.pickup.address, 'PRIVATE_ADDRESS');
  for (const secret of ['PRIVATE_CODE', 'PRIVATE_EVIDENCE', f.customer]) assert.equal(JSON.stringify(courier).includes(secret), false);
  record.kind = 'dispute';
  await assert.rejects(service.readDelivery(id, f.customer), error => error.getStatus() === 403);
  record.kind = 'delivery'; record.encrypted_payload.tag = Buffer.alloc(16).toString('base64');
  await assert.rejects(service.readDelivery(id, f.customer), error => error.getStatus() === 503);
  state = null;
  await assert.rejects(service.readDelivery(id, f.customer), error => error.getStatus() === 403);
});

test('target guard refuses remote/production writes, including dry-run audit writes', () => {
  const local = { DATABASE_URL: 'postgresql://localhost:55432/monosfer_v2_test', NODE_ENV: 'test' };
  for (const mode of ['apply', 'dry_run']) {
    assert.ok(assertImportTarget(local, mode, false));
    for (const env of [{ ...local, NODE_ENV: 'production' }, { DATABASE_URL: 'postgresql://example.com/monosfer_v2_test' }, { DATABASE_URL: 'postgresql://localhost/production' }]) {
      assert.throws(() => assertImportTarget(env, mode, false), /confirm-production-import/);
      assert.ok(assertImportTarget(env, mode, true));
    }
  }
});

class PrivateProbe { fail() { throw new Error(privateSecrets.join(' ')); } }
Controller('private-probe')(PrivateProbe);
Get()(PrivateProbe.prototype, 'fail', Object.getOwnPropertyDescriptor(PrivateProbe.prototype, 'fail'));
class PrivateProbeModule {}
Module({ controllers: [PrivateProbe] })(PrivateProbeModule);
test('private data errors and logs are sanitized; legacy private records have no public endpoint', async t => {
  const { app, logger, logs, document } = await testApplication({ imports: [PrivateProbeModule], redis: { ping: async()=>true, increment: async()=>1 } });
  t.after(() => app.close());
  const response = await app.inject('/v1/private-probe');
  assert.equal(response.statusCode, 500);
  assert.equal(response.json().error.code, 'INTERNAL_ERROR');
  logger.info({ payload: privateFixtures().delivery, pickup: 'PRIVATE_ADDRESS', deliveryCode: 'PRIVATE_CODE', evidence: 'PRIVATE_EVIDENCE', nested: { pushToken: 'PRIVATE_PUSH' } });
  for (const secret of privateSecrets) assert.equal((logs.join('') + response.body).includes(secret), false);
  assert.deepEqual(Object.entries(document.paths).filter(([path, methods]) => path.startsWith('/v1/deliveries') && Object.keys(methods).some(method => method !== 'get')).map(([path])=>path).sort(),
    ['/v1/deliveries/{id}/evidence','/v1/deliveries/{id}/pickup-acceptances','/v1/deliveries/{id}/pod-attestations','/v1/deliveries/{id}/return-acceptances','/v1/deliveries/{id}/tracking/location','/v1/deliveries/{id}/tracking/sessions']);
  assert.equal((await app.inject('/v1/private-records/legacy-id')).statusCode,404);
  assert.equal((await app.inject('/v1/deliveries/0/evidence/00000000-0000-4000-8000-000000000000/content')).statusCode,401);
});
