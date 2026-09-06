import { Injectable, Module, type OnApplicationShutdown, type OnModuleInit } from '@nestjs/common';
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
  onApplicationShutdown(): void {
    if (this.client.isOpen) this.client.destroy();
  }
}

@Module({ providers: [RedisService], exports: [RedisService] })
export class RedisModule {}
