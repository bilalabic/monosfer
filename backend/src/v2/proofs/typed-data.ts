import { hashTypedData, type Address, type TypedData } from 'viem';
export const acceptanceTypes={PickupAcceptance:[{name:'deliveryId',type:'uint256'},{name:'courier',type:'address'},
  {name:'action',type:'bytes32'},{name:'nonce',type:'uint256'},{name:'expiresAt',type:'uint64'}]} as const;
export const attestationTypes={PodAttestation:[{name:'deliveryId',type:'uint256'},{name:'courier',type:'address'},
  {name:'proofType',type:'bytes32'},{name:'challengeHash',type:'bytes32'},{name:'nonce',type:'uint256'},
  {name:'issuedAt',type:'uint64'},{name:'expiresAt',type:'uint64'}]} as const;
export type ProofKind='pickup'|'return'|'pod';
export function proofTypedData(kind:ProofKind,message:Record<string,string>,chainId:number,hub:Address) {
  const types:TypedData=kind==='pod'?attestationTypes:acceptanceTypes;
  const primaryType=kind==='pod'?'PodAttestation':'PickupAcceptance';
  const typedData={domain:{name:'MONOSFER',version:'1',chainId,verifyingContract:hub},types,primaryType,message};
  // viem accepts decimal strings for ABI integers; keep the HTTP representation JSON-safe.
  return {typedData,digest:hashTypedData(typedData)};
}
