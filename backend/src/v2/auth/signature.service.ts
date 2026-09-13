import { Injectable } from '@nestjs/common';
import { createViemConfig, SiweMessage } from '@signinwithethereum/siwe';
import { createPublicClient, http } from 'viem';
import { ConfigService } from '../config/config.js';

@Injectable()
export class SignatureService {
  private readonly verificationConfig;
  constructor(private readonly config: ConfigService) {
    const client = createPublicClient({ transport: http(config.settings.siweRpcUrl, { timeout: config.settings.connectionTimeoutMs, retryCount: 0 }) });
    // Query actual RPC chain ID; do not trust a configured chain object. Only
    // deployed ERC-1271 wallets are supported (no ERC-6492 deployment simulation).
    this.verificationConfig = createViemConfig({ publicClient: { getChainId: () => client.getChainId(), readContract: args => client.readContract(args) } });
  }
  async verify(message: SiweMessage, signature: string, nonce: string): Promise<boolean> {
    const settings = this.config.settings;
    try {
      const result = await message.verify({ signature, nonce, domain: settings.siweDomain,
        uri: settings.siweUri, chainId: settings.siweChainId, time: new Date().toISOString() },
      { config: await this.verificationConfig, strict: true, suppressExceptions: true });
      return result.success;
    } catch { return false; }
  }
}
