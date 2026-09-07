import { Global, Inject, Injectable, Module, type DynamicModule } from '@nestjs/common';
import { parsePrivateKey, type PrivateKeySettings } from '../private-data/crypto.js';
import { parseIndexerSettings, type IndexerSettings } from '../indexer/config.js';
import { parseQuoteSettings, type QuoteSettings } from '../quotes/config.js';

export interface Settings extends PrivateKeySettings {
  indexer: IndexerSettings;
  quotes: QuoteSettings;
  environment: 'development' | 'test' | 'production';
  host: string;
  port: number;
  databaseUrl: string;
  redisUrl: string;
  corsOrigins: string[];
  trustProxy: boolean;
  bodyLimit: number;
  connectionTimeoutMs: number;
  siweDomain: string;
  siweUri: string;
  siweChainId: number;
  siweStatement: string;
  siweRpcUrl: string;
  sessionCookieSecret: string;
  sessionTtlSeconds: number;
  nonceTtlSeconds: number;
  authRateLimitWindowSeconds: number;
  authRateLimitMax: number;
}

const SETTINGS = Symbol('SETTINGS');

export function parseSettings(env: NodeJS.ProcessEnv): Settings {
  const environment = env.NODE_ENV ?? 'development';
  if (!['development', 'test', 'production'].includes(environment)) throw new Error('Invalid NODE_ENV');
  const integer = (key: string, fallback: number, min: number, max: number): number => {
    const raw = env[key] ?? String(fallback);
    if (!/^\d+$/.test(raw)) throw new Error(`Invalid ${key}`);
    const value = Number(raw);
    if (!Number.isSafeInteger(value) || value < min || value > max) throw new Error(`Invalid ${key}`);
    return value;
  };
  const endpoint = (key: string, protocols: string[]): string => {
    const value = env[key];
    try {
      if (!value) throw new Error();
      const parsed = new URL(value);
      if (!protocols.includes(parsed.protocol) || !parsed.hostname || parsed.hash) throw new Error();
      return value;
    } catch { throw new Error(`Invalid ${key}`); }
  };
  const corsOrigins = (env.CORS_ORIGINS ?? '').split(',').map(value => value.trim()).filter(Boolean);
  if (!corsOrigins.length) throw new Error('Invalid CORS_ORIGINS');
  for (const origin of corsOrigins) {
    try {
      const url = new URL(origin);
      if (!['http:', 'https:'].includes(url.protocol) || url.origin !== origin) throw new Error();
    } catch { throw new Error('Invalid CORS_ORIGINS'); }
  }
  const host = env.HOST ?? '127.0.0.1';
  if (!host.trim() || /[\s/]/.test(host)) throw new Error('Invalid HOST');
  const proxy = env.TRUST_PROXY ?? 'false';
  if (!['true', 'false'].includes(proxy)) throw new Error('Invalid TRUST_PROXY');
  const required = (key: string): string => {
    const value = env[key];
    if (!value || value.trim() !== value || /[\r\n]/.test(value)) throw new Error(`Invalid ${key}`);
    return value;
  };
  const requiredInteger = (key: string, min: number, max: number) => {
    required(key);
    return integer(key, 0, min, max);
  };
  const siweUri = endpoint('SIWE_URI', ['http:', 'https:']);
  const uri = new URL(siweUri);
  const siweDomain = required('SIWE_DOMAIN');
  if (uri.host !== siweDomain || uri.username || uri.password || !corsOrigins.includes(uri.origin)) throw new Error('Invalid SIWE_DOMAIN');
  if (environment === 'production' && uri.protocol !== 'https:') throw new Error('Invalid SIWE_URI');
  const siweStatement = required('SIWE_STATEMENT');
  if (siweStatement.length > 200 || /[^\x20-\x7e]/.test(siweStatement)) throw new Error('Invalid SIWE_STATEMENT');
  const sessionCookieSecret = required('SESSION_COOKIE_SECRET');
  if (sessionCookieSecret.length < 32 || sessionCookieSecret.length > 256) throw new Error('Invalid SESSION_COOKIE_SECRET');
  const siweRpcUrl = endpoint('SIWE_RPC_URL', ['http:', 'https:']);
  if (environment === 'production' && new URL(siweRpcUrl).protocol !== 'https:') throw new Error('Invalid SIWE_RPC_URL');
  const siweChainId = requiredInteger('SIWE_CHAIN_ID', 1, 2147483647);
  const indexer = parseIndexerSettings(env);
  if (indexer.enabled && indexer.chainId !== siweChainId) throw new Error('Invalid INDEXER_CHAIN_ID');
  return {
    ...parsePrivateKey(env),
    indexer,
    quotes: parseQuoteSettings(env),
    environment: environment as Settings['environment'], host,
    port: integer('PORT', 3001, 1, 65535),
    databaseUrl: endpoint('DATABASE_URL', ['postgres:', 'postgresql:']),
    redisUrl: endpoint('REDIS_URL', ['redis:', 'rediss:']),
    corsOrigins, trustProxy: proxy === 'true',
    bodyLimit: integer('BODY_LIMIT_BYTES', 65536, 1024, 1048576),
    connectionTimeoutMs: integer('CONNECTION_TIMEOUT_MS', 2000, 100, 10000),
    siweDomain, siweUri, siweStatement, siweRpcUrl, sessionCookieSecret,
    siweChainId,
    sessionTtlSeconds: requiredInteger('SESSION_TTL_SECONDS', 1, 2592000),
    nonceTtlSeconds: requiredInteger('NONCE_TTL_SECONDS', 1, 300),
    authRateLimitWindowSeconds: requiredInteger('AUTH_RATE_LIMIT_WINDOW_SECONDS', 1, 3600),
    authRateLimitMax: requiredInteger('AUTH_RATE_LIMIT_MAX', 1, 1000),
  };
}

@Injectable()
export class ConfigService {
  constructor(@Inject(SETTINGS) readonly settings: Settings) {}
}

@Global()
@Module({})
export class ConfigModule {
  static register(settings: Settings): DynamicModule {
    return { module: ConfigModule, providers: [{ provide: SETTINGS, useValue: settings }, ConfigService], exports: [ConfigService] };
  }
}
