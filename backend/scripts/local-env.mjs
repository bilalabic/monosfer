import { readFile } from 'node:fs/promises';
import { mnemonicToAccount } from 'viem/accounts';

// These are Anvil's publicly known test accounts, never user wallet keys.
export const localAccount = index => mnemonicToAccount(process.env.LOCAL_TEST_MNEMONIC || 'test test test test test test test test test test test junk', { addressIndex: index });
export const root = new URL('../../', import.meta.url);
export const localRpc = 'http://127.0.0.1:8545';
export async function localEnv() {
  const launch = JSON.parse(await readFile(new URL('.claude/launch.json', root), 'utf8'));
  const args = launch.configurations.find(item => item.name === 'backend').runtimeArgs;
  const configured = Object.fromEntries(args.filter(item => /^[A-Z_][A-Z_0-9]*=/.test(item)).map(item => [item.slice(0,item.indexOf('=')),item.slice(item.indexOf('=')+1)]));
  const env = { ...process.env, ...configured, NODE_ENV: 'development', HOST: '127.0.0.1',
    SIWE_CHAIN_ID: '31337', SIWE_RPC_URL: localRpc, INDEXER_ENABLED: 'true', INDEXER_CHAIN_ID: '31337', INDEXER_RPC_URL: localRpc,
    INDEXER_STALE_SECONDS: '120',
    QUOTE_LINK_WORKER_ENABLED: 'true', QUOTE_SIGNER_PRIVATE_KEY: localAccount(2).getHdKey().privateKey && `0x${Buffer.from(localAccount(2).getHdKey().privateKey).toString('hex')}`,
    POD_ATTESTATION_SIGNER_PRIVATE_KEY: `0x${Buffer.from(localAccount(3).getHdKey().privateKey).toString('hex')}`,
    NUXT_PUBLIC_CHAIN_ID: '31337', NUXT_PUBLIC_API_BASE: '/v1' };
  const db = new URL(env.DATABASE_URL);
  if (!['127.0.0.1','localhost'].includes(db.hostname) || db.pathname !== '/monosfer_v2') throw new Error('Local fixtures require the local monosfer_v2 database');
  return env;
}
