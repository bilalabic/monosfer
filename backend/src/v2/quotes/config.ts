import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { privateKeyToAccount } from 'viem/accounts';
import type { Abi, Address, Hex } from 'viem';

export interface QuoteBundle { abi: Abi; configAbi: Abi; chains: Record<string, { hub: Address; config: Address }>; fingerprint: string }
export function loadQuoteBundle(): QuoteBundle {
  try {
    const { fingerprint, ...source } = JSON.parse(readFileSync(new URL('./contracts.json', import.meta.url), 'utf8')) as QuoteBundle;
    if (createHash('sha256').update(JSON.stringify(source)).digest('hex') !== fingerprint) throw new Error();
    return { ...source, fingerprint };
  } catch { throw new Error('Invalid quote contract bundle; run backend build'); }
}
export interface QuoteSettings {
  signerPrivateKey?: Hex; ttlSeconds: number; idempotencyTtlSeconds: number;
  workerEnabled: boolean; pollMs: number; adapterMode: 'deterministic';
}
// The local fixture chain is usable only in development against loopback RPC.
export function supportsQuoteNetwork(environment: string, chainId: number, rpcUrl: string): boolean {
  if (environment === 'production') return false;
  if (chainId === 10143) return true;
  if (environment !== 'development' || chainId !== 31337) return false;
  try {
    const url = new URL(rpcUrl);
    return url.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname) && !url.username && !url.password;
  } catch { return false; }
}
export function parseQuoteSettings(env: NodeJS.ProcessEnv): QuoteSettings {
  const integer = (key: string, fallback: number, min: number, max: number) => {
    const raw = env[key] ?? String(fallback); const value = Number(raw);
    if (!/^\d+$/.test(raw) || !Number.isSafeInteger(value) || value < min || value > max) throw new Error(`Invalid ${key}`);
    return value;
  };
  const signerPrivateKey = env.QUOTE_SIGNER_PRIVATE_KEY || undefined;
  if (signerPrivateKey) {
    try { if (!/^0x[0-9a-fA-F]{64}$/.test(signerPrivateKey)) throw new Error(); privateKeyToAccount(signerPrivateKey as Hex); }
    catch { throw new Error('Invalid QUOTE_SIGNER_PRIVATE_KEY'); }
  }
  const enabled = env.QUOTE_LINK_WORKER_ENABLED ?? 'false';
  if (!['true', 'false'].includes(enabled)) throw new Error('Invalid QUOTE_LINK_WORKER_ENABLED');
  if ((env.RISK_ADAPTER_MODE ?? 'deterministic') !== 'deterministic') throw new Error('Invalid RISK_ADAPTER_MODE');
  const ttlSeconds = integer('QUOTE_TTL_SECONDS', 300, 1, 3600);
  const idempotencyTtlSeconds = integer('QUOTE_IDEMPOTENCY_TTL_SECONDS', 86400, ttlSeconds, 2592000);
  if (enabled === 'true' && (env.INDEXER_ENABLED !== 'true' || !supportsQuoteNetwork(env.NODE_ENV ?? 'development', Number(env.INDEXER_CHAIN_ID ?? '10143'), env.INDEXER_RPC_URL ?? ''))) throw new Error('Invalid QUOTE_LINK_WORKER_ENABLED');
  return { signerPrivateKey: signerPrivateKey as Hex | undefined, ttlSeconds, idempotencyTtlSeconds,
    workerEnabled: enabled === 'true', pollMs: integer('QUOTE_LINK_WORKER_POLL_MS', 2000, 250, 60000), adapterMode: 'deterministic' };
}
