import 'reflect-metadata';
import { Test } from '@nestjs/testing';
import { AppModule, createAdapter, configureApplication } from '../../dist/app.js';
import { parseSettings } from '../../dist/config/config.js';
import { DatabaseService } from '../../dist/infrastructure/database.module.js';
import { RedisService } from '../../dist/infrastructure/redis.module.js';
import { createLogger } from '../../dist/http/logger.js';
import { authEnv } from './env.mjs';
import { AuthRepository } from '../../dist/auth/auth.repository.js';
import { UsersRepository } from '../../dist/users/users.repository.js';

export const testEnv = {
  ...authEnv,
  NODE_ENV: 'test', DATABASE_URL: 'postgresql://test:private-password@127.0.0.1:1/test',
  REDIS_URL: 'redis://127.0.0.1:1', CORS_ORIGINS: 'https://app.example.com', CONNECTION_TIMEOUT_MS: '100',
};

export async function testApplication(options = {}) {
  const settings = { ...parseSettings({ ...testEnv, ...options.env }), ...options.settings };
  const logs = [];
  const logger = createLogger({ write: line => { logs.push(String(line)); } });
  const database = options.database ?? { ping: async () => true, onApplicationShutdown: () => {} };
  const redis = options.redis ?? { ping: async () => true, onApplicationShutdown: () => {} };
  const builder = Test.createTestingModule({ imports: [AppModule.register(settings), ...(options.imports ?? [])] })
    .overrideProvider(DatabaseService).useValue(database)
    .overrideProvider(RedisService).useValue(redis);
  if (options.authRepository) builder.overrideProvider(AuthRepository).useValue(options.authRepository);
  if (options.usersRepository) builder.overrideProvider(UsersRepository).useValue(options.usersRepository);
  for (const [provider,value] of options.providers??[]) builder.overrideProvider(provider).useValue(value);
  const module = await builder.compile();
  const app = module.createNestApplication(createAdapter(settings, logger), { logger: false });
  const document = await configureApplication(app, settings);
  return { app, logs, document, logger };
}
