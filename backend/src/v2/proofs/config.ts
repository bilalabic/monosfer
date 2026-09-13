import type { Hex } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
export interface ProofSettings { signerPrivateKey?: Hex; podTtl: number; acceptanceTtl: number; idempotencyTtl: number }
export function parseProofSettings(env: NodeJS.ProcessEnv): ProofSettings {
  const integer=(key:string,fallback:number,max:number)=>{
    const value=env[key]??String(fallback);
    if(!/^\d+$/.test(value)||!Number.isSafeInteger(Number(value))||Number(value)<1||Number(value)>max)throw new Error(`Invalid ${key}`);
    return Number(value);
  };
  const signerPrivateKey=env.POD_ATTESTATION_SIGNER_PRIVATE_KEY || undefined;
  if(signerPrivateKey)try {
    if(!/^0x[0-9a-fA-F]{64}$/.test(signerPrivateKey))throw new Error();
    privateKeyToAccount(signerPrivateKey as Hex);
    if(env.QUOTE_SIGNER_PRIVATE_KEY?.toLowerCase()===signerPrivateKey.toLowerCase())throw new Error();
  } catch {throw new Error('Invalid POD_ATTESTATION_SIGNER_PRIVATE_KEY');}
  return {signerPrivateKey:signerPrivateKey as Hex|undefined,podTtl:integer('POD_ATTESTATION_TTL_SECONDS',300,600),
    acceptanceTtl:integer('PROOF_ACCEPTANCE_TTL_SECONDS',300,3600),idempotencyTtl:integer('PROOF_IDEMPOTENCY_TTL_SECONDS',86400,604800)};
}
