import { mkdir, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { ABIS, CHAINS } from '../../contracts/exports/index.js';

// Generated backend build artifact; upstream exports remain the only source of ABI/address data.
const source = { abi: ABIS.DeliveryHub, chains: Object.fromEntries(Object.entries(CHAINS).flatMap(([id, chain]) => {
  const hub = chain.contracts.DeliveryHub;
  return hub && !hub.legacy ? [[id, { chainId: chain.chainId, ...hub }]] : [];
})) };
const fingerprint = createHash('sha256').update(JSON.stringify(source)).digest('hex');
await mkdir(new URL('../dist/indexer/', import.meta.url), { recursive: true });
await writeFile(new URL('../dist/indexer/contracts.json', import.meta.url), JSON.stringify({ ...source, fingerprint }) + '\n');
// Separate artifact: adding quote config ABI does not invalidate existing indexer fingerprints.
const quotes = { abi: ABIS.DeliveryHub, configAbi: ABIS.ProtocolConfig,
  chains: Object.fromEntries(Object.entries(CHAINS).flatMap(([id, chain]) => {
    const hub = chain.contracts.DeliveryHub; const config = chain.contracts.ProtocolConfig;
    return hub && !hub.legacy && config && !config.legacy ? [[id, { hub: hub.address, config: config.address }]] : [];
  })) };
if (!quotes.configAbi || !quotes.abi.some(item => item.name === 'hashQuote')) throw new Error('Missing quote contract exports');
await mkdir(new URL('../dist/quotes/', import.meta.url), { recursive: true });
await writeFile(new URL('../dist/quotes/contracts.json', import.meta.url), JSON.stringify({ ...quotes,
  fingerprint: createHash('sha256').update(JSON.stringify(quotes)).digest('hex') }) + '\n');
