import 'reflect-metadata';
import { randomUUID } from 'node:crypto';
import { Module, ValidationPipe, type DynamicModule } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { FastifyAdapter, type NestFastifyApplication } from '@nestjs/platform-fastify';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import helmet from '@fastify/helmet';
import { LogController } from 'fastify';
import type { Logger } from 'pino';
import { ConfigModule, parseSettings, type Settings } from './config/config.js';
import { HealthModule } from './health/health.module.js';
import { ApiExceptionFilter } from './http/errors.js';
import { createLogger, FrameworkLogger } from './http/logger.js';

@Module({})
export class AppModule {
  static register(settings: Settings): DynamicModule {
    return { module: AppModule, imports: [ConfigModule.register(settings), HealthModule] };
  }
}

export function createAdapter(settings: Settings, logger: Logger): FastifyAdapter {
  return new FastifyAdapter({
    loggerInstance: logger, logController: new LogController({ disableRequestLogging: true }),
    requestIdHeader: false, genReqId: () => randomUUID(),
    bodyLimit: settings.bodyLimit, trustProxy: settings.trustProxy,
    requestTimeout: 10000,
  });
}

export async function configureApplication(app: NestFastifyApplication, settings: Settings) {
  app.setGlobalPrefix('v1');
  app.useGlobalPipes(new ValidationPipe({ transform: true, whitelist: true, forbidNonWhitelisted: true, validationError: { target: false, value: false } }));
  app.useGlobalFilters(new ApiExceptionFilter());
  await app.register(helmet);
  app.enableCors({ origin: settings.corsOrigins, credentials: true, exposedHeaders: ['x-request-id'] });
  const server = app.getHttpAdapter().getInstance();
  server.addHook('onRequest', async (request, reply) => {
    reply.header('x-request-id', request.id);
    reply.header('cache-control', 'no-store');
  });
  server.addHook('onResponse', async (request, reply) => {
    request.log.info({ event: 'http_response', requestId: request.id, statusCode: reply.statusCode });
  });
  const document = SwaggerModule.createDocument(app, new DocumentBuilder().setTitle('Monosfer V2 Backend').setVersion('1.0.0').build());
  document.components ??= {};
  document.components.schemas ??= {};
  document.components.schemas.ApiError = {
    type: 'object', required: ['error'], properties: {
      error: { type: 'object', required: ['code', 'message', 'requestId'], properties: {
        code: { type: 'string' }, message: { type: 'string' }, requestId: { type: 'string', format: 'uuid' },
      } },
    },
  };
  const ready = document.paths['/v1/health/ready']?.get;
  if (ready) ready.responses['503'] = { description: 'Service unavailable', content: { 'application/json': { schema: { $ref: '#/components/schemas/ApiError' } } } };
  SwaggerModule.setup('v1/docs', app, document, { ui: settings.environment === 'development', raw: ['json'], jsonDocumentUrl: '/v1/openapi.json' });
  await app.init();
  await server.ready();
  return document;
}

export async function createApplication(env: NodeJS.ProcessEnv = process.env, logger = createLogger()) {
  const settings = parseSettings(env);
  const app = await NestFactory.create<NestFastifyApplication>(AppModule.register(settings), createAdapter(settings, logger), { logger: new FrameworkLogger(logger), abortOnError: false });
  try {
    await configureApplication(app, settings);
    return { app, settings };
  } catch (error) { await app.close(); throw error; }
}
