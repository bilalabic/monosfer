import { Controller, Get, Injectable, Module, ServiceUnavailableException } from '@nestjs/common';
import { ApiOkResponse, ApiServiceUnavailableResponse, ApiTags, ApiProperty } from '@nestjs/swagger';
import { DatabaseModule, DatabaseService } from '../infrastructure/database.module.js';
import { RedisModule, RedisService } from '../infrastructure/redis.module.js';

class HealthResponse {
  @ApiProperty({ enum: ['ok'] })
  status!: string;
}

@Injectable()
export class HealthService {
  constructor(private readonly database: DatabaseService, private readonly redis: RedisService) {}
  async ready(): Promise<HealthResponse> {
    const checks = await Promise.allSettled([this.database.ping(), this.redis.ping()]);
    if (checks.some(check => check.status !== 'fulfilled' || !check.value)) throw new ServiceUnavailableException();
    return { status: 'ok' };
  }
}

@ApiTags('health')
@Controller('health')
export class HealthController {
  constructor(private readonly health: HealthService) {}
  @Get('live')
  @ApiOkResponse({ type: HealthResponse })
  live(): HealthResponse { return { status: 'ok' }; }
  @Get('ready')
  @ApiOkResponse({ type: HealthResponse })
  @ApiServiceUnavailableResponse({ description: 'A required dependency is unavailable.' })
  ready(): Promise<HealthResponse> { return this.health.ready(); }
}

@Module({ imports: [DatabaseModule, RedisModule], providers: [HealthService], controllers: [HealthController] })
export class HealthModule {}
