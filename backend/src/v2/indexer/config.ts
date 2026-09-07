import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import type { Abi, Address } from 'viem';

export interface Deployment { chainId: number; address: Address; block: number }
export interface Bundle { abi: Abi; chains: Record<string, Deployment>; fingerprint: string }
// Bootstrap-only artifact load; no filesystem reads in the HTTP request path.
export function loadBundle(): Bundle {
  try {
    const bundle = JSON.parse(readFileSync(new URL('./contracts.json', import.meta.url), 'utf8')) as Bundle;
    const fingerprint = createHash('sha256').update(JSON.stringify({ abi: bundle.abi, chains: bundle.chains })).digest('hex');
    if (fingerprint !== bundle.fingerprint || !Array.isArray(bundle.abi)) throw new Error();
    return bundle;
  } catch { throw new Error('Invalid contract export bundle; run backend build'); }
}
export interface IndexerSettings {
  enabled: boolean; chainId: number; rpcUrl: string; batchSize: number; pollMs: number;
  maxLag: number; staleSeconds: number; reorgDepth: number;
  deployment?: Deployment; fingerprint?: string;
}
export function parseIndexerSettings(env: NodeJS.ProcessEnv): IndexerSettings {
  const enabled = env.INDEXER_ENABLED ?? 'false';
  if (!['true', 'false'].includes(enabled)) throw new Error('Invalid INDEXER_ENABLED');
  const integer = (key: string, fallback: number, min: number, max: number) => {
    const value = env[key] ?? String(fallback);
    if (!/^\d+$/.test(value) || !Number.isSafeInteger(Number(value)) || Number(value) < min || Number(value) > max) throw new Error(`Invalid ${key}`);
    return Number(value);
  };
  const chainId = integer('INDEXER_CHAIN_ID', 10143, 1, 2147483647);
  const rpcUrl = env.INDEXER_RPC_URL ?? '';
  let bundle: Bundle | undefined;
  if (enabled === 'true') {
    bundle = loadBundle();
    if (!bundle.chains[chainId]) throw new Error('Unsupported INDEXER_CHAIN_ID');
    try {
      const url = new URL(rpcUrl);
      if (!['http:', 'https:'].includes(url.protocol) || url.hash || !url.hostname || (env.NODE_ENV === 'production' && url.protocol !== 'https:')) throw new Error();
    } catch { throw new Error('Invalid INDEXER_RPC_URL'); }
  }
  return { enabled: enabled === 'true', chainId, rpcUrl, deployment: bundle?.chains[chainId], fingerprint: bundle?.fingerprint,
    batchSize: integer('INDEXER_BATCH_SIZE', 100, 1, 200), pollMs: integer('INDEXER_POLL_MS', 2000, 250, 60000),
    maxLag: integer('INDEXER_MAX_LAG_BLOCKS', 20, 0, 10000), staleSeconds: integer('INDEXER_STALE_SECONDS', 30, 5, 3600),
    reorgDepth: integer('INDEXER_REORG_DEPTH', 64, 1, 1000) };
}
