import { createPublicClient, http, type Abi, type Address, type Hex } from 'viem';
import type { ChainBlock, ChainLog } from './events.js';

export interface IndexerRpc {
  chainId(): Promise<number>; code(address: Address): Promise<Hex | undefined>;
  block(number: bigint | 'finalized'): Promise<ChainBlock>;
  logs(address: Address, from: bigint, to: bigint): Promise<ChainLog[]>;
  read(address: Address, abi: Abi, name: string, args: unknown[], block: bigint): Promise<unknown>;
}
export class HubRpc implements IndexerRpc {
  private readonly client;
  constructor(url: string, signal?: AbortSignal) { this.client = createPublicClient({ transport: http(url, { timeout: 5000, retryCount: 1, retryDelay: 250, fetchOptions: { signal } }) }); }
  chainId() { return this.client.getChainId(); }
  code(address: Address) { return this.client.getCode({ address, blockTag: 'finalized' }); }
  async block(number: bigint | 'finalized'): Promise<ChainBlock> {
    const b = await this.client.getBlock(typeof number === 'bigint' ? { blockNumber: number } : { blockTag: number });
    if (b.number === null || (typeof number === 'bigint' && b.number !== number) || !b.hash || !/^0x[0-9a-fA-F]{64}$/.test(b.hash) || !/^0x[0-9a-fA-F]{64}$/.test(b.parentHash)) throw new Error('Invalid RPC block');
    return { number: b.number, hash: b.hash.toLowerCase() as Hex, parentHash: b.parentHash.toLowerCase() as Hex };
  }
  async logs(address: Address, fromBlock: bigint, toBlock: bigint): Promise<ChainLog[]> {
    const logs = await this.client.getLogs({ address, fromBlock, toBlock });
    return logs.map(log => {
      if (log.blockNumber === null || !log.blockHash || !log.transactionHash || log.transactionIndex === null || log.logIndex === null) throw new Error('Incomplete RPC log');
      return { ...log, blockNumber: log.blockNumber, blockHash: log.blockHash, transactionHash: log.transactionHash, transactionIndex: log.transactionIndex, logIndex: log.logIndex };
    });
  }
  read(address: Address, abi: Abi, functionName: string, args: unknown[], blockNumber: bigint) {
    return this.client.readContract({ address, abi, functionName, args, blockNumber });
  }
}
