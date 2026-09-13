import { createPublicClient, http, type Address, type Hex } from 'viem';
import { loadBundle } from '../indexer/config.js';
import { HubRpc } from '../indexer/rpc.js';
import { loadQuoteBundle } from '../quotes/config.js';
import { typedQuote, quoteTypes } from '../quotes/typed-data.js';
import { proofTypedData } from '../proofs/typed-data.js';

// Public RPC only: this module has no account/signer or transaction transport.
export async function testnetSmoke(url: string) {
  let stage='configuration';
  const checks: string[]=[];
  try {
    const endpoint=new URL(url);
    if(!['http:','https:'].includes(endpoint.protocol))throw new Error();
    const bundle=loadBundle(),quotes=loadQuoteBundle(),deployment=bundle.chains[10143],quoteDeployment=quotes.chains[10143];
    if(!deployment || !quoteDeployment || deployment.address.toLowerCase()!==quoteDeployment.hub.toLowerCase())throw new Error();
    const hashFunction=quotes.abi.find(item=>item.type==='function'&&item.name==='hashQuote');
    if(!hashFunction || hashFunction.type!=='function' || !('components' in hashFunction.inputs[0]!) ||
      JSON.stringify(hashFunction.inputs[0].components.map(({name,type})=>({name,type})))!==JSON.stringify(quoteTypes.Quote))throw new Error();
    stage='chain';
    const client=createPublicClient({transport:http(url,{timeout:5000,retryCount:0})});
    if(await client.getChainId()!==10143)throw new Error();checks.push(stage);
    stage='finalized_block';
    const block=await client.getBlock({blockTag:'finalized'}),now=BigInt(Math.floor(Date.now()/1000));
    if(block.number===null || !block.hash || block.timestamp>now+5n || block.timestamp<now-120n || block.number<BigInt(deployment.block))throw new Error();
    checks.push(stage);stage='deployment_code';
    for(const address of [deployment.address,quoteDeployment.config]) {
      const code=await client.getCode({address,blockNumber:block.number});if(!code||code==='0x')throw new Error();
    }
    checks.push(stage);stage='protocol_config';
    const config=await client.readContract({address:deployment.address,abi:quotes.abi,functionName:'config',blockNumber:block.number});
    if(String(config).toLowerCase()!==quoteDeployment.config.toLowerCase())throw new Error();
    const read=(functionName:string,args?:unknown[])=>client.readContract({address:quoteDeployment.config,abi:quotes.configAbi,functionName,args,blockNumber:block.number!});
    const validity=Number(await read('riskQuoteValidity'));
    const signer=String(await read('riskQuoteSigner'));
    if(!Number.isSafeInteger(validity)||validity<1||!/^0x[0-9a-fA-F]{40}$/.test(signer)||/^0x0{40}$/.test(signer))throw new Error();
    for(const tier of [1,2,3])if(BigInt(String(await read('coverageBpsForTier',[tier])))<=0n)throw new Error();
    const minimum=BigInt(String(await read('coverageMultiplierMinBps'))),maximum=BigInt(String(await read('coverageMultiplierMaxBps')));
    if(minimum<=0n || maximum<minimum)throw new Error();
    checks.push(stage);stage='hash_quote';
    const quote={customer:deployment.address as Address,riskTier:1,declaredValue:'1',requiredCoverage:'1',issuedAt:String(block.timestamp),
      expiresAt:String(block.timestamp+BigInt(Math.min(300,validity))),salt:`0x${'11'.repeat(32)}` as Hex};
    const {quoteDigest}=typedQuote(quote,10143,deployment.address,validity);
    const hash=await client.readContract({address:deployment.address,abi:quotes.abi,functionName:'hashQuote',args:[quote],blockNumber:block.number});
    if(hash!==quoteDigest)throw new Error();checks.push(stage);stage='proof_hashes';
    const hubRead=(functionName:string,args:unknown[]=[])=>client.readContract({address:deployment.address,abi:quotes.abi,functionName,args,blockNumber:block.number!});
    const action=String(await hubRead('pickupAction'));
    const returnAction=String(await hubRead('returnAction'));
    const proofTypes=await hubRead('podProofTypes') as string[];
    for(const kind of ['pickup','return','pod'] as const) {
      const message:Record<string,string>={deliveryId:'0',courier:deployment.address,nonce:'1',expiresAt:String(block.timestamp+60n)};
      if(kind==='pod')Object.assign(message,{proofType:proofTypes[0],challengeHash:`0x${'22'.repeat(32)}`,issuedAt:String(block.timestamp)});
      else message.action=kind==='pickup'?action:returnAction;
      const expected=proofTypedData(kind,message,10143,deployment.address).digest;
      if(await hubRead(kind==='pod'?'hashPodAttestation':'hashPickupAcceptance',[message])!==expected)throw new Error();
    }
    checks.push(stage);stage='indexer_read';
    const rpc=new HubRpc(url),height=block.number;
    const indexed=await rpc.block(height);
    if(indexed.hash!==block.hash.toLowerCase())throw new Error();
    await rpc.logs(deployment.address,height,height);
    if(deployment.court) {
      if(!(await rpc.code(deployment.court.address))||await rpc.code(deployment.court.address)==='0x')throw new Error();
      await rpc.logs(deployment.court.address,height,height);
    }
    if((await client.getBlock({blockNumber:height})).hash!==block.hash)throw new Error();
    checks.push(stage);
    return {status:'passed' as const,checks,chainId:10143,finalizedBlock:String(height),exportFingerprint:bundle.fingerprint,transactionsSent:0};
  } catch { return {status:'failed' as const,stage,checks,code:'TESTNET_SMOKE_FAILED',transactionsSent:0}; }
}
