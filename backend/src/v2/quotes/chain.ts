import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { createPublicClient, http, type Address, type Hex } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { ConfigService } from '../config/config.js';
import { loadQuoteBundle } from './config.js';
import { quoteTypes, typedQuote, type CoverageQuote } from './typed-data.js';
import type { RiskPolicy } from './risk.js';

export interface QuoteSnapshot extends RiskPolicy {
  block: bigint; timestamp: bigint; blockHash: Hex; signer: Address;
}
@Injectable()
export class QuoteChain {
  readonly bundle = loadQuoteBundle();
  constructor(private readonly config: ConfigService) {
    const definition = this.bundle.abi.find(item=>item.type==='function' && item.name==='hashQuote');
    if (!definition || definition.type!=='function' || !('components' in definition.inputs[0]!) ||
      JSON.stringify(definition.inputs[0].components.map(({name,type})=>({name,type})))!==JSON.stringify(quoteTypes.Quote)) {
      throw new Error('Quote ABI mismatch');
    }
  }
  assertAvailable(): void {
    const s = this.config.settings; const deployment = this.bundle.chains[s.indexer.chainId];
    if (s.environment === 'production' || s.indexer.chainId !== 10143 || !s.indexer.enabled || !s.quotes.signerPrivateKey ||
      !deployment || deployment.hub.toLowerCase() !== s.indexer.deployment?.address.toLowerCase()) throw new ServiceUnavailableException();
  }
  private client() {
    this.assertAvailable();
    return createPublicClient({ transport: http(this.config.settings.indexer.rpcUrl, { timeout: 2000, retryCount: 0 }) });
  }
  private deployment() { return this.bundle.chains[this.config.settings.indexer.chainId]!; }
  async snapshot(): Promise<QuoteSnapshot> {
    try {
      const client = this.client(); const d = this.deployment();
      const [chainId, block] = await Promise.all([client.getChainId(), client.getBlock({ blockTag: 'finalized' })]);
      const now = BigInt(Math.floor(Date.now()/1000));
      if (chainId !== this.config.settings.indexer.chainId || block.number === null || !block.hash ||
        block.timestamp > now+5n || block.timestamp < now-BigInt(this.config.settings.indexer.staleSeconds)) throw new Error();
      const read = (functionName: string, args?: readonly unknown[]) => client.readContract({ abi:this.bundle.configAbi,
        address:d.config, functionName, args, blockNumber:block.number! });
      const [configAddress, code, signer, validity, coverageBps, minBps, maxBps] = await Promise.all([
        client.readContract({ abi:this.bundle.abi,address:d.hub,functionName:'config',blockNumber:block.number }),
        client.getCode({ address:d.hub, blockNumber:block.number }), read('riskQuoteSigner'), read('riskQuoteValidity'),
        read('coverageBpsForTier',[1]), read('coverageMultiplierMinBps'), read('coverageMultiplierMaxBps'),
      ]);
      if (!code || code==='0x' || String(configAddress).toLowerCase()!==d.config.toLowerCase() ||
        String(signer).toLowerCase()!==privateKeyToAccount(this.config.settings.quotes.signerPrivateKey!).address.toLowerCase() ||
        this.config.settings.quotes.ttlSeconds > Number(validity)) throw new Error();
      return { block:block.number, blockHash:block.hash, timestamp:block.timestamp, signer:signer as Address,
        validity:Number(validity), coverageBps:BigInt(String(coverageBps)), minBps:BigInt(String(minBps)), maxBps:BigInt(String(maxBps)) };
    } catch { throw new ServiceUnavailableException(); }
  }
  async redeemed(digest: Hex, snapshot: QuoteSnapshot): Promise<boolean> {
    try { return await this.client().readContract({ address:this.deployment().hub,abi:this.bundle.abi,
      functionName:'quoteRedeemed',args:[digest],blockNumber:snapshot.block }) as boolean; }
    catch { throw new ServiceUnavailableException(); }
  }
  async verifyHash(quote: CoverageQuote, digest: Hex, snapshot: QuoteSnapshot): Promise<void> {
    try {
      const client = this.client();
      const result = await client.readContract({ address:this.deployment().hub,abi:this.bundle.abi,functionName:'hashQuote',
        args:[quote],blockNumber:snapshot.block });
      const block = await client.getBlock({ blockNumber:snapshot.block });
      if (result !== digest || block.hash !== snapshot.blockHash) throw new Error();
    } catch { throw new ServiceUnavailableException(); }
  }
}
@Injectable()
export class QuoteSigner {
  constructor(private readonly config: ConfigService, private readonly chain: QuoteChain) {}
  async sign(quote: CoverageQuote, snapshot: QuoteSnapshot) {
    this.chain.assertAvailable();
    const settings = this.config.settings;
    const signed = typedQuote(quote, settings.indexer.chainId, settings.indexer.deployment!.address, snapshot.validity);
    await this.chain.verifyHash(quote, signed.quoteDigest, snapshot);
    const signature = await privateKeyToAccount(settings.quotes.signerPrivateKey!).signTypedData({ ...signed.typedData,
      message: { ...quote, declaredValue:BigInt(quote.declaredValue),requiredCoverage:BigInt(quote.requiredCoverage),
        issuedAt:BigInt(quote.issuedAt),expiresAt:BigInt(quote.expiresAt) } });
    return { ...signed, signature };
  }
}
