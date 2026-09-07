import { BadRequestException, Injectable, UnauthorizedException } from '@nestjs/common';
import { SiweMessage } from '@signinwithethereum/siwe';
import { getAddress } from 'viem';
import { ConfigService } from '../config/config.js';
import { RedisService } from '../infrastructure/redis.module.js';
import { csrf, hash, token } from '../security/tokens.js';
import { AuthRepository } from './auth.repository.js';
import { SignatureService } from './signature.service.js';
import type { SessionResponseDto } from './auth.dto.js';

export interface AuthContext extends SessionResponseDto { sessionHash: string; }
@Injectable()
export class AuthService {
  constructor(private readonly config: ConfigService, private readonly redis: RedisService,
    private readonly repository: AuthRepository, private readonly signatures: SignatureService) {}

  async nonce(rawAddress: string) {
    let address: string;
    try { address = getAddress(rawAddress); } catch { throw new BadRequestException(); }
    const settings = this.config.settings;
    const nonce = token();
    const browserToken = token();
    const expiresAt = new Date(Date.now() + settings.nonceTtlSeconds * 1000).toISOString();
    const message = new SiweMessage({ domain: settings.siweDomain, address, uri: settings.siweUri,
      version: '1', chainId: settings.siweChainId, statement: settings.siweStatement, nonce,
      issuedAt: new Date().toISOString(), expirationTime: expiresAt }).prepareMessage();
    await this.redis.set(`auth:nonce:${hash(nonce)}`, JSON.stringify({ messageHash: hash(message), browserHash: hash(browserToken) }), settings.nonceTtlSeconds);
    return { response: { address, nonce, message, expiresAt }, browserToken };
  }
  async verify(rawMessage: string, signature: string, browserToken: string | undefined) {
    let message: SiweMessage;
    try { message = new SiweMessage(rawMessage); } catch { throw new UnauthorizedException(); }
    if (!browserToken || !/^[a-f0-9]{64}$/.test(browserToken)) throw new UnauthorizedException();
    const key = `auth:nonce:${hash(message.nonce)}`;
    const stored = await this.redis.get(key);
    const expected = JSON.stringify({ messageHash: hash(rawMessage), browserHash: hash(browserToken) });
    // Bind every SIWE field to the server-issued message and originating browser.
    if (stored !== expected || !message.expirationTime || Date.parse(message.expirationTime) <= Date.now()
      || !await this.signatures.verify(message, signature, message.nonce)) throw new UnauthorizedException();
    if (!await this.redis.consume(key, expected)) throw new UnauthorizedException();
    const sessionId = token();
    const sessionHash = hash(sessionId);
    const settings = this.config.settings;
    const expiresAt = new Date(Date.now() + settings.sessionTtlSeconds * 1000).toISOString();
    const user = await this.repository.createSession(message.address, sessionHash, expiresAt);
    try {
      await this.redis.set(`auth:session:${sessionHash}`, user.id, settings.sessionTtlSeconds);
    } catch (error) {
      await this.repository.revoke(sessionHash, user.id, false);
      throw error;
    }
    return { sessionId, response: { user, session: { expiresAt }, csrfToken: csrf(sessionId, settings.sessionCookieSecret) } };
  }
  async authenticate(sessionId: string | undefined): Promise<AuthContext> {
    if (!sessionId || !/^[a-f0-9]{64}$/.test(sessionId)) throw new UnauthorizedException();
    const sessionHash = hash(sessionId);
    const userId = await this.redis.get(`auth:session:${sessionHash}`);
    if (!userId) throw new UnauthorizedException();
    const record = await this.repository.findSession(sessionHash);
    if (!record || record.user.id !== userId) throw new UnauthorizedException();
    return { user: record.user, session: { expiresAt: record.expiresAt }, sessionHash,
      csrfToken: csrf(sessionId, this.config.settings.sessionCookieSecret) };
  }
  async revoke(context: AuthContext, all: boolean) {
    const hashes = await this.repository.revoke(context.sessionHash, context.user.id, all);
    await this.redis.del(hashes.map(value => `auth:session:${value}`));
  }
}
