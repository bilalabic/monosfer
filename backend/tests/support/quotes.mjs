import { createServer } from 'node:http';
import { once } from 'node:events';
import { generatePrivateKey, privateKeyToAccount } from 'viem/accounts';
import { encodeAbiParameters, parseAbiParameters, keccak256, stringToHex, concatHex, decodeFunctionData, encodeFunctionResult, toHex } from 'viem';
import { ConfigService, parseSettings } from '../../dist/config/config.js';
import { QuoteChain } from '../../dist/quotes/chain.js';
import { testEnv } from './app.mjs';
import { hubFixture, hashOf } from './indexer.mjs';

// Independent Solidity abi.encode + keccak implementation of CoverageQuote.hash and EIP712.
// Does not call typedQuote/hashTypedData: catches field order, widths, struct and domain drift.
export function solidityHashQuote(quote, chainId, hub) {
  const domain=keccak256(encodeAbiParameters(parseAbiParameters('bytes32,bytes32,bytes32,uint256,address'),[
    keccak256(stringToHex('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')),
    keccak256(stringToHex('MONOSFER')),keccak256(stringToHex('1')),BigInt(chainId),hub]));
  const struct=keccak256(encodeAbiParameters(parseAbiParameters('bytes32,address,uint8,uint96,uint96,uint64,uint64,bytes32'),[
    keccak256(stringToHex('Quote(address customer,uint8 riskTier,uint96 declaredValue,uint96 requiredCoverage,uint64 issuedAt,uint64 expiresAt,bytes32 salt)')),
    quote.customer,quote.riskTier,BigInt(quote.declaredValue),BigInt(quote.requiredCoverage),BigInt(quote.issuedAt),BigInt(quote.expiresAt),quote.salt]));
  return keccak256(concatHex(['0x1901',domain,struct]));
}
export function quoteFixture() {
  const account=privateKeyToAccount(generatePrivateKey());const signerKey=generatePrivateKey();
  const signer=privateKeyToAccount(signerKey);const hub=hubFixture(account.address);
  const settings={...parseSettings(testEnv),indexer:hub.settings};
  settings.quotes={...settings.quotes,signerPrivateKey:signerKey,workerEnabled:true};
  const config=new ConfigService(settings);const chain=new QuoteChain(config);
  const configAddress=privateKeyToAccount(generatePrivateKey()).address;
  chain.bundle.chains[10143]={hub:hub.address,config:configAddress};
  return {account,signer,signerKey,hub,settings,config,chain,configAddress,requests:[],redeemed:new Set(),
    chainId:10143,validity:300,coverageBps:5000,minBps:7500,maxBps:15000,stale:false,badHash:false,badSigner:false,badConfig:false,badBlock:false,fail:false};
}
export async function quoteRpcServer(f) {
  const server=createServer(async(request,response)=>{
    let text='';for await(const chunk of request)text+=chunk;
    const call=JSON.parse(text);f.requests.push(call.method);
    const [a,b]=call.params??[];let result;
    try {
      if(f.fail)throw new Error();
      if(call.method==='eth_chainId') result=toHex(f.chainId);
      else if(call.method==='eth_getCode') result='0x60016001';
      else if(call.method==='eth_getBlockByNumber')result={number:toHex(102),hash:hashOf(f.badBlock && a!=='finalized'?'changed':'quote-block'),parentHash:hashOf('parent'),transactions:[],
        timestamp:toHex(Math.floor(Date.now()/1000)-(f.stale?120:0)),gasLimit:'0x1',gasUsed:'0x0',size:'0x1',difficulty:'0x0',extraData:'0x',nonce:'0x0000000000000000',miner:f.account.address,logsBloom:`0x${'0'.repeat(512)}`};
      else if(call.method==='eth_call'){
        const abi=a.to.toLowerCase()===f.hub.address?f.chain.bundle.abi:f.chain.bundle.configAbi;
        const {functionName,args}=decodeFunctionData({abi,data:a.data});
        if(b!=='0x66')throw new Error('All reads must use the same finalized height');
        let value;
        switch(functionName){
          case 'config':value=f.badConfig?f.account.address:f.configAddress;break;
          case 'riskQuoteSigner':value=f.badSigner?f.account.address:f.signer.address;break;
          case 'riskQuoteValidity':value=f.validity;break;
          case 'coverageBpsForTier':value=f.coverageBps;break;
          case 'coverageMultiplierMinBps':value=f.minBps;break;
          case 'coverageMultiplierMaxBps':value=f.maxBps;break;
          case 'quoteRedeemed':value=f.redeemed.has(args[0]);break;
          case 'hashQuote':value=f.badHash?hashOf('bad-hash'):solidityHashQuote(args[0],f.chainId,f.hub.address);break;
          default:throw new Error('Unexpected method');
        }
        result=encodeFunctionResult({abi,functionName,result:value});
      }else throw new Error('Unexpected RPC write');
      response.setHeader('content-type','application/json');response.end(JSON.stringify({jsonrpc:'2.0',id:call.id,result}));
    }catch{response.end(JSON.stringify({jsonrpc:'2.0',id:call.id,error:{code:-32603,message:'QUOTE_RPC_PRIVATE_SECRET'}}));}
  });
  server.listen(0,'127.0.0.1');await once(server,'listening');
  f.settings.indexer.rpcUrl=`http://127.0.0.1:${server.address().port}`;
  return {close:()=>new Promise(resolve=>server.close(resolve))};
}
export const quoteInput=()=>({declaredValue:'10000',metadata:{packageType:'document',urgency:'standard'},
  privatePayload:{pickup:{address:'QUOTE_PRIVATE_PICKUP',lat:41,lng:29,contactPhone:'+905551234567'},
    dropoff:{address:'QUOTE_PRIVATE_DROPOFF',lat:40,lng:28,contactPhone:'+905552345678',recipientName:'QUOTE_PRIVATE_NAME',deliveryCode:'QUOTE_PRIVATE_CODE'},notes:'QUOTE_PRIVATE_NOTES'}});
