import { Global, Inject, Injectable, Module, type DynamicModule } from '@nestjs/common';

export interface Settings {
  environment: 'development' | 'test' | 'production';
  host: string;
  port: number;
  databaseUrl: string;
  redisUrl: string;
  corsOrigins: string[];
  trustProxy: boolean;
  bodyLimit: number;
  connectionTimeoutMs: number;
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
  return {
    environment: environment as Settings['environment'], host,
    port: integer('PORT', 3001, 1, 65535),
    databaseUrl: endpoint('DATABASE_URL', ['postgres:', 'postgresql:']),
    redisUrl: endpoint('REDIS_URL', ['redis:', 'rediss:']),
    corsOrigins, trustProxy: proxy === 'true',
    bodyLimit: integer('BODY_LIMIT_BYTES', 65536, 1024, 1048576),
    connectionTimeoutMs: integer('CONNECTION_TIMEOUT_MS', 2000, 100, 10000),
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
