import { createServer } from 'node:http';
import { once } from 'node:events';
import { generatePrivateKey, privateKeyToAccount } from 'viem/accounts';
import { encodeAbiParameters, parseAbiParameters, keccak256, stringToHex, concatHex, decodeFunctionData, encodeFunctionResult, toHex } from 'viem';
import { ProofChain } from '../../dist/proofs/chain.js';
import { hashOf } from './indexer.mjs';

// Independent Solidity abi.encode construction, deliberately not hashTypedData.
export function solidityProofHash(kind,m,chainId,hub) {
  const domain=keccak256(encodeAbiParameters(parseAbiParameters('bytes32,bytes32,bytes32,uint256,address'),[
    keccak256(stringToHex('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')),
    keccak256(stringToHex('MONOSFER')),keccak256(stringToHex('1')),BigInt(chainId),hub]));
  const pod=kind==='pod';
  const type=pod?'PodAttestation(uint256 deliveryId,address courier,bytes32 proofType,bytes32 challengeHash,uint256 nonce,uint64 issuedAt,uint64 expiresAt)':
    'PickupAcceptance(uint256 deliveryId,address courier,bytes32 action,uint256 nonce,uint64 expiresAt)';
  const values=pod?[BigInt(m.deliveryId),m.courier,m.proofType,m.challengeHash,BigInt(m.nonce),BigInt(m.issuedAt),BigInt(m.expiresAt)]:
    [BigInt(m.deliveryId),m.courier,m.action,BigInt(m.nonce),BigInt(m.expiresAt)];
  const struct=keccak256(encodeAbiParameters(parseAbiParameters(pod?'bytes32,uint256,address,bytes32,bytes32,uint256,uint64,uint64':'bytes32,uint256,address,bytes32,uint256,uint64'),[keccak256(stringToHex(type)),...values]));
  return keccak256(concatHex(['0x1901',domain,struct]));
}
export async function proofRpc(config,customer,courier) {
  const signerKey=generatePrivateKey(); config.settings.proofs.signerPrivateKey=signerKey;
  const chain=new ProofChain(config); const hub=config.settings.indexer.deployment.address;
  const configAddress=privateKeyToAccount(generatePrivateKey()).address;
  chain.bundle.chains[10143]={hub,config:configAddress};
  const f={chain,signer:privateKeyToAccount(signerKey),customer:customer.toLowerCase(),courier:courier.toLowerCase(),hub,chainId:10143,
    state:3,used:false,badHash:false,badDomain:false,badSigner:false,stale:false,fail:false,validity:600,requests:[],hash:hashOf('ops-block')};
  const server=createServer(async(req,res)=>{
    let body='';for await(const chunk of req)body+=chunk;
    const call=JSON.parse(body);f.requests.push(call.method);
    try {
      if(f.fail)throw new Error();
      const [a]=call.params??[];let result;const now=BigInt(Math.floor(Date.now()/1000));
      if(call.method==='eth_chainId')result=toHex(f.chainId);
      else if(call.method==='eth_getBlockByNumber')result={number:toHex(102),hash:f.hash,parentHash:hashOf('parent'),timestamp:toHex(now-(f.stale?120n:0n)),transactions:[],gasLimit:'0x1',gasUsed:'0x0',size:'0x1',difficulty:'0x0',extraData:'0x',nonce:'0x0000000000000000',miner:customer,logsBloom:`0x${'0'.repeat(512)}`};
      else if(call.method==='eth_call') {
        const abi=a.to.toLowerCase()===hub.toLowerCase()?chain.bundle.abi:chain.bundle.configAbi;
        const {functionName,args}=decodeFunctionData({abi,data:a.data});let value;
        switch(functionName) {
          case 'eip712Domain':value=['0x0f',f.badDomain?'OTHER':'MONOSFER','1',10143n,hub,hashOf('salt'),[]];break;
          case 'deliveryOf':value={customer:f.customer,courier:f.courier,state:f.state,riskTier:1,termsVersion:1,stateDeadline:now+600n,etaDeadline:now+300n,etaMinutes:5,completedAt:0n,courierAsk:1n,protocolFee:1n,returnReserve:1n,requiredCollateral:1n,customerFunded:true,courierFunded:true};break;
          case 'pickupAction':value=keccak256(stringToHex('MONOSFER.PICKUP'));break;
          case 'returnAction':value=keccak256(stringToHex('MONOSFER.RETURN'));break;
          case 'config':value=configAddress;break;
          case 'podProofTypes':value=['MONOSFER.POD.OTP','MONOSFER.POD.QR','MONOSFER.POD.RECIPIENT_SIGNATURE'].map(x=>keccak256(stringToHex(x)));break;
          case 'podAttestationSigner':value=f.badSigner?customer:f.signer.address;break;
          case 'podAttestationValidity':value=f.validity;break;
          case 'pickupNonceUsed':case 'podNonceUsed':value=f.used;break;
          case 'hashPickupAcceptance':case 'hashPodAttestation':value=f.badHash?hashOf('wrong'):solidityProofHash(functionName==='hashPodAttestation'?'pod':'pickup',args[0],10143,hub);break;
          default:throw new Error();
        }
        result=encodeFunctionResult({abi,functionName,result:value});
      }else throw new Error();
      res.end(JSON.stringify({jsonrpc:'2.0',id:call.id,result}));
    }catch{res.end(JSON.stringify({jsonrpc:'2.0',id:call.id,error:{code:-32603,message:'PROOF_RPC_PRIVATE_SECRET'}}));}
  });
  server.listen(0,'127.0.0.1');await once(server,'listening');config.settings.indexer.rpcUrl=`http://127.0.0.1:${server.address().port}`;
  return {...f,get fixture(){return f;},close:()=>new Promise(resolve=>server.close(resolve))};
}
