import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { privateKeyToAccount } from 'viem/accounts';
import type { Address, Hex } from 'viem';
import { ConfigService } from '../config/config.js';
import { loadQuoteBundle } from '../quotes/config.js';
import { HubRpc } from '../indexer/rpc.js';
import { states } from '../indexer/events.js';
import { proofTypedData, acceptanceTypes, attestationTypes, type ProofKind } from './typed-data.js';
export interface ProofSnapshot {block:bigint;hash:Hex;timestamp:bigint;action?:string;proofType?:string;signer?:Address;validity:number}
@Injectable()
export class ProofChain {
  readonly bundle=loadQuoteBundle();
  constructor(private readonly config:ConfigService) {
    for(const [name,fields] of [['hashPickupAcceptance',acceptanceTypes.PickupAcceptance],['hashPodAttestation',attestationTypes.PodAttestation]] as const) {
      const fn=this.bundle.abi.find(e=>e.type==='function'&&e.name===name);
      if(!fn||fn.type!=='function'||!('components' in fn.inputs[0]!)||JSON.stringify(fn.inputs[0].components.map(({name,type})=>({name,type})))!==JSON.stringify(fields))throw new Error('Proof ABI mismatch');
    }
  }
  private connection() {
    const s=this.config.settings; const d=this.bundle.chains[s.indexer.chainId];
    if(!s.indexer.enabled||!d||d.hub.toLowerCase()!==s.indexer.deployment?.address.toLowerCase())throw new ServiceUnavailableException();
    return {s,d,rpc:new HubRpc(s.indexer.rpcUrl)};
  }
  async snapshot(kind:ProofKind,id:string,data:Record<string,string>,block:string,hash:string):Promise<ProofSnapshot> {
    try {
      const {s,d,rpc}=this.connection(); const head=await rpc.block('finalized'); const now=BigInt(Math.floor(Date.now()/1000));
      if(await rpc.chainId()!==s.indexer.chainId||head.timestamp>now+5n||head.timestamp<now-BigInt(s.indexer.staleSeconds))throw new Error();
      if((await rpc.block(BigInt(block))).hash!==hash||head.number<BigInt(block))throw new Error();
      const read=(name:string,args:unknown[]=[])=>rpc.read(d.hub,this.bundle.abi,name,args,head.number);
      const [domain,onchain]=await Promise.all([read('eip712Domain'),read('deliveryOf',[BigInt(id)])]);
      const fields=domain as unknown[]; const chain=onchain as Record<string,unknown>;
      if(fields[0]!=='0x0f'||fields[1]!=='MONOSFER'||fields[2]!=='1'||Number(fields[3])!==s.indexer.chainId||String(fields[4]).toLowerCase()!==d.hub.toLowerCase()||
        !Array.isArray(fields[6])||fields[6].length||states[Number(chain.state)]!==data.state||String(chain.customer).toLowerCase()!==data.customer||String(chain.courier).toLowerCase()!==data.courier)throw new Error();
      if(BigInt(String(chain.stateDeadline))<now)throw new Error();
      const snapshot:ProofSnapshot={block:head.number,hash:head.hash,timestamp:head.timestamp,validity:s.proofs.acceptanceTtl};
      if(kind!=='pod')snapshot.action=String(await read(kind==='pickup'?'pickupAction':'returnAction'));
      else {
        if(!s.proofs.signerPrivateKey)throw new Error();
        const configAddress=await read('config');
        if(String(configAddress).toLowerCase()!==d.config.toLowerCase())throw new Error();
        const [types,signer,validity]=await Promise.all([read('podProofTypes'),rpc.read(d.config,this.bundle.configAbi,'podAttestationSigner',[],head.number),rpc.read(d.config,this.bundle.configAbi,'podAttestationValidity',[],head.number)]);
        if(String(signer).toLowerCase()!==privateKeyToAccount(s.proofs.signerPrivateKey).address.toLowerCase()||s.proofs.podTtl>Number(validity))throw new Error();
        snapshot.proofType=String((types as unknown[])[0]); snapshot.signer=signer as Address; snapshot.validity=s.proofs.podTtl;
      }
      return snapshot;
    }catch{throw new ServiceUnavailableException();}
  }
  async finish(kind:ProofKind,message:Record<string,string>,snapshot:ProofSnapshot,customer:string) {
    try {
      const {s,d,rpc}=this.connection(); const signed=proofTypedData(kind,message,s.indexer.chainId,d.hub);
      const [digest,used,block]=await Promise.all([
        rpc.read(d.hub,this.bundle.abi,kind==='pod'?'hashPodAttestation':'hashPickupAcceptance',[message],snapshot.block),
        rpc.read(d.hub,this.bundle.abi,kind==='pod'?'podNonceUsed':'pickupNonceUsed',[kind==='pod'?snapshot.signer:customer,BigInt(message.nonce!)],snapshot.block),rpc.block(snapshot.block)]);
      if(digest!==signed.digest||used!==false||block.hash!==snapshot.hash)throw new Error();
      const signature=kind==='pod'?await privateKeyToAccount(s.proofs.signerPrivateKey!).signTypedData(signed.typedData):undefined;
      return {...signed,...(signature?{signature}:{})};
    }catch{throw new ServiceUnavailableException();}
  }
}
