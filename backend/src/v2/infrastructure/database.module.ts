import { Injectable, Module, type OnApplicationShutdown } from '@nestjs/common';
import { Pool, type PoolClient, type QueryResultRow } from 'pg';
import { ConfigService } from '../config/config.js';

@Injectable()
export class DatabaseService implements OnApplicationShutdown {
  private readonly pool: Pool;
  constructor(config: ConfigService) {
    this.pool = new Pool({
      connectionString: config.settings.databaseUrl,
      max: 10,
      connectionTimeoutMillis: config.settings.connectionTimeoutMs,
      query_timeout: config.settings.connectionTimeoutMs,
      statement_timeout: config.settings.connectionTimeoutMs,
      idleTimeoutMillis: 10000,
    });
    // Readiness reports failures; never log connection errors containing credentials.
    this.pool.on('error', () => {});
  }
  async query<T extends QueryResultRow>(sql: string, parameters: unknown[] = []) {
    return this.pool.query<T>(sql, parameters);
  }
  async ping(): Promise<boolean> {
    try { await this.query('SELECT 1'); return true; } catch { return false; }
  }
  async transaction<T>(work: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const result = await work(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally { client.release(); }
  }
  async onApplicationShutdown(): Promise<void> { await this.pool.end(); }
}

@Module({ providers: [DatabaseService], exports: [DatabaseService] })
export class DatabaseModule {}
