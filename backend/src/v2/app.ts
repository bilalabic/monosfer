import 'reflect-metadata';
import { randomUUID } from 'node:crypto';
import { Module, ValidationPipe, type DynamicModule } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { FastifyAdapter, type NestFastifyApplication } from '@nestjs/platform-fastify';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import helmet from '@fastify/helmet';
import cookie from '@fastify/cookie';
import { AuthModule } from './auth/auth.module.js';
import { UsersModule } from './users/users.module.js';
import { PrivateDataModule } from './private-data/private-data.module.js';
import { IndexerReadModule } from './indexer/read.module.js';
import { QuotesModule } from './quotes/quotes.module.js';
import { TrackingApiModule } from './tracking/tracking.module.js';
import { TrackingRealtimeModule } from './tracking/realtime.js';
import { ProvidersModule } from './providers/providers.module.js';
import { SupportModule } from './support/support.module.js';
import { ReputationModule } from './reputation/reputation.module.js';
import { OpsModule } from './ops/ops.module.js';
import { OpsService } from './ops/ops.service.js';
import { cookieNames } from './security/tokens.js';
import { LogController } from 'fastify';
import type { Logger } from 'pino';
import { ConfigModule, parseSettings, type Settings } from './config/config.js';
import { HealthModule } from './health/health.module.js';
import { ApiExceptionFilter } from './http/errors.js';
import { createLogger, FrameworkLogger } from './http/logger.js';

@Module({})
export class AppModule {
  static register(settings: Settings): DynamicModule {
    return { module: AppModule, imports: [ConfigModule.register(settings), HealthModule, AuthModule, UsersModule, PrivateDataModule, IndexerReadModule, QuotesModule, TrackingApiModule, ProvidersModule, SupportModule, ReputationModule, OpsModule] };
  }
}

@Module({})
export class RealtimeAppModule {
  static register(settings:Settings):DynamicModule{return {module:RealtimeAppModule,imports:[ConfigModule.register(settings),HealthModule,TrackingRealtimeModule]};}
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
  await app.register(cookie);
  app.enableCors({ origin: settings.corsOrigins, credentials: true, exposedHeaders: ['x-request-id', 'retry-after'],
    methods: ['GET', 'HEAD', 'POST', 'PATCH', 'DELETE', 'OPTIONS'], allowedHeaders: ['content-type', 'x-csrf-token', 'idempotency-key', 'x-tracking-session', 'last-event-id'] });
  const server = app.getHttpAdapter().getInstance();
  server.addHook('onRequest', async (request, reply) => {
    reply.header('x-request-id', request.id);
    reply.header('cache-control', 'no-store');
  });
  server.addHook('onResponse', async (request, reply) => {
    request.log.info({ event: 'http_response', requestId: request.id, statusCode: reply.statusCode });
    // Realtime process intentionally has no SQL telemetry dependency.
    if (ops) await ops.observe(request.id, reply.statusCode, reply.elapsedTime);
  });
  let ops: OpsService | undefined;
  try { ops = app.get(OpsService); } catch { /* Realtime application. */ }
  const document = SwaggerModule.createDocument(app, new DocumentBuilder().setTitle('Monosfer V2 Backend').setVersion('2.0.0')
    .addCookieAuth(cookieNames(settings).session, { type: 'apiKey', in: 'cookie' }, 'session')
    .addBearerAuth({type:'http',scheme:'bearer'},'ops').build());
  document.components ??= {};
  document.components.schemas ??= {};
  for (const name of ['NonceInputDto', 'VerifyInputDto', 'UpdateUserDto', 'CourierProfileDto', 'DeliveryQueryDto', 'DeliveryIdDto', 'BidQueryDto',
    'CreateQuoteDto','QuoteMetadataDto','QuoteLocationDto','QuoteDropoffDto','QuotePrivatePayloadDto','QuoteDigestDto','RefreshQuoteDto',
    'TrackingLocationDto','TrackingEmptyDto','EvidenceInputDto','EvidenceGpsDto','DeliveryEvidenceIdDto','NotificationQueryDto',
    'CaseCreateDto','CasePatchDto','CaseIdDto','SupportEvidenceIdDto','WalletIdDto','TraceIdDto','SupportPageDto','AuditPageDto']) {
    const schema = document.components.schemas[name];
    if (schema && !('$ref' in schema)) schema.additionalProperties = false;
  }
  document.components.schemas.ApiError = {
    type: 'object', required: ['error'], properties: {
      error: { type: 'object', required: ['code', 'message', 'requestId'], properties: {
        code: { type: 'string' }, message: { type: 'string' }, requestId: { type: 'string', format: 'uuid' },
      } },
    },
  };
  const ready = document.paths['/v1/health/ready']?.get;
  if (ready) ready.responses['503'] = { description: 'Service unavailable', content: { 'application/json': { schema: { $ref: '#/components/schemas/ApiError' } } } };
  for (const [path, item] of Object.entries(document.paths)) {
    if (!['auth','users','deliveries','indexer','quotes','notifications','support','admin','ops'].some(prefix=>path.startsWith(`/v1/${prefix}`))) continue;
    for (const method of ['get', 'post', 'patch', 'delete'] as const) {
      const operation = item?.[method];
      if (operation) for (const status of ['400', '401', '403', '404', '409', '429', '503']) {
        operation.responses[status] = { description: 'Standard API error', content: { 'application/json': { schema: { $ref: '#/components/schemas/ApiError' } } } };
      }
    }
  }
  SwaggerModule.setup('v1/docs', app, document, { ui: settings.environment === 'development', raw: ['json'], jsonDocumentUrl: '/v1/openapi.json' });
  await app.init();
  await server.ready();
  return document;
}

export async function createApplication(env: NodeJS.ProcessEnv = process.env, logger = createLogger(), realtime=false) {
  const settings = parseSettings(env);
  const app = await NestFactory.create<NestFastifyApplication>((realtime?RealtimeAppModule:AppModule).register(settings), createAdapter(settings, logger), { logger: new FrameworkLogger(logger), abortOnError: false });
  try {
    await configureApplication(app, settings);
    return { app, settings };
  } catch (error) { await app.close(); throw error; }
}
