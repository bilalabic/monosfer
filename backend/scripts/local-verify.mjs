import 'reflect-metadata';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { localEnv, localAccount, root } from './local-env.mjs';
import { ConfigService, parseSettings } from '../dist/config/config.js';
import { DatabaseService } from '../dist/infrastructure/database.module.js';
import { PrivateDataCrypto } from '../dist/private-data/crypto.js';
import { PrivateDataService, PrivateDeliveryProjection, PrivateRecordsRepository } from '../dist/private-data/private-data.module.js';

const config=new ConfigService(parseSettings(await localEnv()));
const db=new DatabaseService(config);
const base='http://localhost:3000';
async function json(path) {const r=await fetch(`${base}/v1${path}`);assert.equal(r.status,200,path);return r.json();}
try {
  const deliveries=await json('/deliveries?limit=100');
  assert.equal(deliveries.indexing.chainId,31337);assert.equal(deliveries.indexing.status,'ready');
  const dataset=await json('/development/dataset');
  assert.equal(dataset.deliveries.length,12);assert.equal(dataset.couriers.length,6);
  const bids=await Promise.all(dataset.deliveries.map(item=>json(`/deliveries/${item.id}/bids?limit=100`)));
  assert.equal(dataset.deliveries.every(item=>deliveries.data.some(d=>d.id===item.id)),true);
  const bidCount=bids.reduce((sum,page)=>sum+page.data.length,0);assert.ok(bidCount>=20);
  const seeded=JSON.parse(await readFile(new URL('backend/.local-seed-progress.local',root),'utf8'));
  const links=await db.query('SELECT count(*)::int AS count FROM monosfer.private_delivery_links WHERE stream=$1',[seeded.stream]);
  assert.equal(links.rows[0].count,12);
  const privateData=new PrivateDataService(new PrivateRecordsRepository(db),new PrivateDataCrypto(config.settings),new PrivateDeliveryProjection(db,config));
  const customer=deliveries.data.find(item=>item.id===seeded.deliveries[0].id).customer;
  const payload=await privateData.readDelivery(seeded.deliveries[0].privateRecordId,customer);
  assert.ok(payload.pickup.address.includes('Kayseri'));
  await assert.rejects(privateData.readDelivery(seeded.deliveries[0].privateRecordId,localAccount(0).address),error=>error.getStatus()===403);
  for(const [path,title] of [['/deliveries','Noter evrakı acil kurye'],['/couriers','Ahmet Yılmaz (Test)']]) {
    const response=await fetch(base+path);assert.equal(response.status,200);
    const html=await response.text();assert.ok(html.includes(title),`${path} did not render fixture content`);
    assert.equal(html.includes('was called outside of a plugin'),false);
  }
  console.log(JSON.stringify({event:'local_dataset_verified',couriers:6,deliveries:12,bids:bidCount,privateLinks:12,ssr:true,privateAccessControl:true}));
}finally{await db.onApplicationShutdown();}
