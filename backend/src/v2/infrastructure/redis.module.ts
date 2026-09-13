import { Injectable, Module, ServiceUnavailableException, type OnApplicationShutdown, type OnModuleInit } from '@nestjs/common';
import { createClient } from 'redis';
import { ConfigService } from '../config/config.js';

@Injectable()
export class RedisService implements OnModuleInit, OnApplicationShutdown {
  private readonly client;
  private readonly timeoutMs: number;
  constructor(config: ConfigService) {
    this.timeoutMs = config.settings.connectionTimeoutMs;
    this.client = createClient({
      url: config.settings.redisUrl,
      disableOfflineQueue: true,
      commandsQueueMaxLength: 100,
      socket: {
        connectTimeout: this.timeoutMs,
        reconnectStrategy: retries => retries < 3 ? Math.min(100 * (retries + 1), 300) : false,
      },
    });
    this.client.on('error', () => {});
  }
  async onModuleInit(): Promise<void> {
    try { await this.client.connect(); } catch { /* Readiness stays unavailable. */ }
  }
  async ping(): Promise<boolean> {
    if (!this.client.isReady) return false;
    try {
      const reply = await this.client.withCommandOptions({ timeout: this.timeoutMs }).ping();
      return reply === 'PONG';
    } catch { return false; }
  }
  async command<T>(work: (client: ReturnType<typeof this.commands>) => Promise<T>): Promise<T> {
    try {
      if (!this.client.isReady) throw new Error();
      return await work(this.commands());
    } catch { throw new ServiceUnavailableException(); }
  }
  private commands() { return this.client.withCommandOptions({ timeout: this.timeoutMs }); }
  async get(key: string) { return this.command(client => client.get(key)); }
  async set(key: string, value: string, ttl: number) { return this.command(client => client.set(key, value, { EX: ttl })); }
  async del(keys: string[]) { if (keys.length) await this.command(client => client.del(keys)); }
  async consume(key: string, expected: string): Promise<boolean> {
    return (await this.command(client => client.eval("if redis.call('GET', KEYS[1]) == ARGV[1] then return redis.call('DEL', KEYS[1]) else return 0 end", { keys: [key], arguments: [expected] }))) === 1;
  }
  async increment(key: string, ttl: number): Promise<number> {
    return Number(await this.command(client => client.eval("local n = redis.call('INCR', KEYS[1]); if n == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end; return n", { keys: [key], arguments: [String(ttl)] })));
  }
  onApplicationShutdown(): void {
    if (this.client.isOpen) this.client.destroy();
  }
}

@Module({ providers: [RedisService], exports: [RedisService] })
export class RedisModule {}
