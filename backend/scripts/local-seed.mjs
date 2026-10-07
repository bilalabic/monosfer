import 'reflect-metadata';
import { randomUUID } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { setTimeout } from 'node:timers/promises';
import { createPublicClient, createWalletClient, http, parseEther, keccak256, stringToHex } from 'viem';
import { foundry } from 'viem/chains';
import { localAccount, localEnv, localRpc, root } from './local-env.mjs';
import { ConfigService, parseSettings } from '../dist/config/config.js';
import { DatabaseService } from '../dist/infrastructure/database.module.js';
import { QuoteChain, QuoteSigner } from '../dist/quotes/chain.js';
import { QuotesRepository } from '../dist/quotes/quotes.repository.js';
import { QuotesService } from '../dist/quotes/quotes.service.js';
import { DeterministicRiskAdapter } from '../dist/quotes/risk.js';
import { proofTypedData } from '../dist/proofs/typed-data.js';

const env=await localEnv();
const config=new ConfigService(parseSettings(env));
const db=new DatabaseService(config);
const client=createPublicClient({chain:foundry,transport:http(localRpc)});
const manifest=JSON.parse(await readFile(new URL('contracts/deployments/31337.json',root),'utf8'));
const hub=manifest.contracts.DeliveryHub.address;
const stream=`31337:${hub}`;
const {ABIS}=await import('../../contracts/exports/index.js');
const hubRead=(name,args=[])=>client.readContract({address:hub,abi:ABIS.DeliveryHub,functionName:name,args});
const chain=new QuoteChain(config);
const quotes=new QuotesService(config,new QuotesRepository(db,config),new DeterministicRiskAdapter(),chain,new QuoteSigner(config,chain));
const wallet=account=>createWalletClient({account,chain:foundry,transport:http(localRpc)});
async function send(account,address,abi,functionName,args=[],value=undefined) {
  const request={account:account.address,address,abi,functionName,args,value};
  await client.simulateContract(request);
  const estimate=await client.estimateContractGas(request);
  const hash=await wallet(account).writeContract({address,abi,functionName,args,value,gas:estimate+estimate/5n});
  const receipt=await client.waitForTransactionReceipt({hash,pollingInterval:250});
  if(receipt.status!=='success')throw new Error(`${functionName} reverted`);
  return receipt;
}
const sendHub=(account,name,args=[],value)=>send(account,hub,ABIS.DeliveryHub,name,args,value);
async function fund(address) {
  if(await client.getBalance({address})<parseEther('100'))await client.request({method:'anvil_setBalance',params:[address,'0x3635c9adc5dea00000']});
}
const vehicles=['motorcycle','bicycle','car','on_foot','motorcycle','bicycle'];
const names=['Ahmet Yılmaz','Selin Yıldız','Mehmet Demir','Ayşe Kaya','Can Erkan','Ece Şahin'];
const couriers=names.map((name,i)=>({walletAddress:localAccount(i+4).address.toLowerCase(),name:`${name} (Test)`,vehicleType:vehicles[i],joinedDate:new Date().toISOString()}));
// Each scenario uses real state transitions. Amounts are test MON, not fiat prices.
const scenarios=[
  ['Erciyes Üniversitesi evrak teslimi','Talas / Mevlana','Melikgazi / Hunat','document','0.4','6.2 km','0.2 kg','Completed',10,0],
  ['İade: yanlış ürün gönderimi','Kocasinan / Sahabiye','Melikgazi / Cumhuriyet','small','0.35','3.8 km','1 kg','Returned',11,1],
  ['Kitap siparişi teslim onayı','Melikgazi / Cumhuriyet','Talas / Yenidoğan','small','0.45','7.1 km','1.5 kg','DeliveredPending',12,2],
  ['Öğle yemeği ofis teslimatı','Melikgazi / Alpaslan','Kocasinan / Mimarsinan','food','0.55','8.4 km','2 kg','InTransit',13,3],
  ['Mağazadan küçük paket alımı','Melikgazi / İldem','Talas / Bahçelievler','small','0.65','10.3 km','3 kg','ReadyForPickup',-1,4],
  ['Çiçek siparişi hızlı teslimat','Kocasinan / Gevhernesibe','Melikgazi / Gültepe','medium','0.5','4.8 km','2.5 kg','AwaitingFunding',-1,5],
  ['Noter evrakı acil kurye','Melikgazi / Hunat','Kocasinan / Sahabiye','document','0.3','2.6 km','0.1 kg','Bidding',-1,0],
  ['Pastaneden doğum günü paketi','Talas / Yenidoğan','Melikgazi / Alpaslan','food','0.6','5.5 km','2 kg','Bidding',-1,1],
  ['Teknoloji mağazası aksesuar paketi','Melikgazi / Cumhuriyet','Talas / Mevlana','small','0.48','6.9 km','0.8 kg','Bidding',10,2],
  ['Atölyeden tekstil numunesi','Kocasinan / Mimarsinan','Melikgazi / İldem','medium','0.75','12 km','4 kg','Bidding',11,3],
  ['İptal: mükerrer sipariş','Talas / Bahçelievler','Talas / Yenidoğan','small','0.28','2.1 km','1 kg','Cancelled',12,4],
  ['Alıcı bulunamadı: iade yolculuğu','Melikgazi / Gültepe','Kocasinan / Gevhernesibe','medium','0.52','4.8 km','3 kg','ReturnRequired',13,0],
];
const progressPath=new URL('backend/.local-seed-progress.local',root);
let progress={stream,deliveries:[]};
try{const saved=JSON.parse(await readFile(progressPath,'utf8'));if(saved.stream===stream)progress=saved;}catch{ /* first seed */ }
const save=()=>writeFile(progressPath,JSON.stringify(progress,null,2)+'\n');
let impersonated;
try {
  if(await client.getChainId()!==31337)throw new Error('Seeding requires local chain 31337');
  // Fresh deployments need to reach Anvil's finalized head before quote signing.
  for(let attempt=0;attempt<90;attempt++) {
    try { await chain.snapshot(); break; }
    catch(error) { if(attempt===89)throw error; if(attempt===0)console.log('Waiting for local deployment finality…'); await setTimeout(1000); }
  }
  // Prefer the already registered tester for the open sender scenarios. No key
  // is requested: impersonation is an Anvil-only capability on this local chain.
  const accounts=new Set(Array.from({length:20},(_,i)=>localAccount(i).address.toLowerCase()));
  const users=(await db.query('SELECT wallet_address FROM monosfer.users ORDER BY updated_at DESC')).rows;
  const tester=process.env.LOCAL_TEST_CUSTOMER || users.find(row=>!accounts.has(row.wallet_address))?.wallet_address || localAccount(14).address;
  if(!/^0x[0-9a-fA-F]{40}$/.test(tester))throw new Error('Invalid test customer');
  await fund(tester);
  await client.request({method:'anvil_impersonateAccount',params:[tester]});
  impersonated=tester;
  for(let i=0;i<couriers.length;i++) {
    const courier=couriers[i]; const account=localAccount(i+4);
    await fund(account.address);
    await db.query(`INSERT INTO monosfer.users(id,wallet_address,role,display_name,courier_profile)
      VALUES($1,$2,'courier',$3,$4) ON CONFLICT(wallet_address) DO UPDATE SET role='courier',display_name=EXCLUDED.display_name,courier_profile=EXCLUDED.courier_profile`,
      [randomUUID(),courier.walletAddress,courier.name,JSON.stringify({vehicleType:courier.vehicleType})]);
    const stake=await client.readContract({address:manifest.contracts.CourierRegistry.address,abi:ABIS.CourierRegistry,functionName:'courierOf',args:[account.address]});
    if(stake.stake<parseEther('60'))await send(account,manifest.contracts.CourierRegistry.address,ABIS.CourierRegistry,'depositStake',[],parseEther('60')-stake.stake);
  }
  for(let i=0;i<scenarios.length;i++) {
    const [title,pickupArea,dropoffArea,packageType,ask,distance,weight,target,customerIndex,courierIndex]=scenarios[i];
    const customer=customerIndex===-1?{address:tester,type:'json-rpc'}:localAccount(customerIndex);
    const courier=localAccount(courierIndex+4);
    await fund(customer.address);
    if(customerIndex!==-1)await db.query(`INSERT INTO monosfer.users(id,wallet_address,role,display_name) VALUES($1,$2,'customer',$3) ON CONFLICT(wallet_address) DO NOTHING`,
      [randomUUID(),customer.address.toLowerCase(),`Örnek Gönderici ${customerIndex-9} (Test)`]);
    let item=progress.deliveries[i];
    if(!item) {
      const issued=await quotes.issue(customer.address,randomUUID(),{declaredValue:parseEther('2').toString(),metadata:{packageType,urgency:packageType==='food'?'express':'standard'},privatePayload:{
        pickup:{address:`Kayseri, ${pickupArea} — örnek teslim alma noktası`,lat:38.721+i*0.0005,lng:35.487+i*0.0005},
        dropoff:{address:`Kayseri, ${dropoffArea} — örnek teslim noktası`,lat:38.704+i*0.001,lng:35.525+i*0.001,recipientName:'Örnek Alıcı (Test)',recipientNote:'Bu kayıt yerel test senaryosudur.'},notes:title}});
      const id=await hubRead('nextDeliveryId');
      const q=issued.quote;
      await sendHub(customer,'createDelivery',[{...q,declaredValue:BigInt(q.declaredValue),requiredCoverage:BigInt(q.requiredCoverage),issuedAt:BigInt(q.issuedAt),expiresAt:BigInt(q.expiresAt)},issued.signature]);
      item={id:String(id),title,pickupArea:`Kayseri · ${pickupArea}`,dropoffArea:`Kayseri · ${dropoffArea}`,distance,weight,description:'Örnek test gönderisi. Sözleşme ve teklifler yerel zincirde kayıtlıdır.',budget:Number(ask),createdAt:new Date().toISOString(),privateRecordId:issued.privateRecordId};
      progress.deliveries[i]=item;await save();
    }
    const id=BigInt(item.id);
    let delivery=await hubRead('deliveryOf',[id]);
    if(Number(delivery.state)===1) {
      const bidCouriers=[];
      for(let offset=0;offset<(target==='Bidding'?6:1);offset++) {
        const index=(courierIndex+offset)%6;
        const existing=await hubRead('bidOf',[id,localAccount(index+4).address]);
        const eligible=await client.readContract({address:manifest.contracts.CourierRegistry.address,abi:ABIS.CourierRegistry,functionName:'isEligibleFor',args:[localAccount(index+4).address,1]});
        if(existing.active || eligible)bidCouriers.push(index);
        if(bidCouriers.length===3)break;
      }
      for(const [j,index] of bidCouriers.entries()) {
        const bidder=localAccount(index+4);
        const bid=await hubRead('bidOf',[id,bidder.address]);
        if(!bid.active)await sendHub(bidder,'placeBid',[id,parseEther(String(Number(ask)+(j*0.05))),parseEther('0.1'),25+j*10,BigInt(Math.floor(Date.now()/1000)+23*3600)]);
      }
      if(target==='Cancelled')await sendHub(customer,'cancelDuringBidding',[id]);
      else if(target!=='Bidding') {
        const bid=await hubRead('bidOf',[id,courier.address]);
        await sendHub(customer,'selectCourier',[id,courier.address,Number(bid.termsVersion)]);
      }
    }
    delivery=await hubRead('deliveryOf',[id]);
    if(Number(delivery.state)===2 && target!=='AwaitingFunding') {
      if(!delivery.customerFunded)await sendHub(customer,'fundAsCustomer',[id],await hubRead('customerFundingAmount',[id]));
      if(!delivery.courierFunded)await sendHub(courier,'fundAsCourier',[id]);
    }
    delivery=await hubRead('deliveryOf',[id]);
    async function acceptance(kind) {
      const message={deliveryId:String(id),courier:courier.address,action:await hubRead(kind==='pickup'?'pickupAction':'returnAction'),nonce:String(BigInt(keccak256(stringToHex(`${stream}:${id}:${kind}`)))),expiresAt:String(Math.floor(Date.now()/1000)+300)};
      const signature=await customer.signTypedData(proofTypedData(kind,message,31337,hub).typedData);
      return [id,message,signature];
    }
    if(Number(delivery.state)===3 && !['ReadyForPickup','AwaitingFunding','Bidding','Cancelled'].includes(target))await sendHub(courier,'confirmPickup',await acceptance('pickup'));
    delivery=await hubRead('deliveryOf',[id]);
    if(Number(delivery.state)===4 && ['Completed','DeliveredPending'].includes(target)) {
      const message={deliveryId:String(id),courier:courier.address,proofType:(await hubRead('podProofTypes'))[0],challengeHash:keccak256(stringToHex(`local-test:${id}`)),nonce:String(BigInt(keccak256(stringToHex(`pod:${stream}:${id}`)))),issuedAt:String(Math.floor(Date.now()/1000)),expiresAt:String(Math.floor(Date.now()/1000)+300)};
      const signature=await localAccount(3).signTypedData(proofTypedData('pod',message,31337,hub).typedData);
      await sendHub(courier,'submitDeliveryProof',[id,message,signature]);
    }
    delivery=await hubRead('deliveryOf',[id]);
    if(Number(delivery.state)===5 && target==='Completed')await sendHub(customer,'confirmDelivery',[id]);
    if(Number(delivery.state)===4 && ['Returned','ReturnRequired'].includes(target))await sendHub(customer,'requestReturn',[id]);
    delivery=await hubRead('deliveryOf',[id]);
    if(Number(delivery.state)===6 && target==='Returned')await sendHub(courier,'confirmReturn',await acceptance('return'));
    const states=['None','Bidding','AwaitingFunding','ReadyForPickup','InTransit','DeliveredPending','ReturnRequired','Disputed','Completed','Returned','Resolved','Cancelled','Expired'];
    if(states[Number((await hubRead('deliveryOf',[id])).state)]!==target)throw new Error(`Scenario ${i+1} did not reach ${target}`);
    console.log(`Scenario ${i+1}/12: #${id} ${target}`);
    // Publish incrementally; only non-private labels are available to the UI.
    const publicDeliveries=progress.deliveries.map(({privateRecordId,...data})=>data);
    await db.query(`INSERT INTO monosfer.development_datasets(stream,data) VALUES($1,$2) ON CONFLICT(stream) DO UPDATE SET data=EXCLUDED.data,updated_at=now()`,[stream,JSON.stringify({couriers,deliveries:publicDeliveries})]);
  }
  console.log('Seed complete: 6 courier profiles, 12 delivery scenarios; rerunning resumes without duplicating deliveries.');
} catch(error) {
  console.error(error.shortMessage || error.message || 'Local fixture seed failed');
  process.exitCode=1;
} finally {
  if(impersonated)await client.request({method:'anvil_stopImpersonatingAccount',params:[impersonated]}).catch(()=>{});
  await db.onApplicationShutdown();
}
