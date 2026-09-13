import { CanActivate, ExecutionContext, ForbiddenException, HttpException, Injectable, Module } from '@nestjs/common';
import type { FastifyRequest, FastifyReply } from 'fastify';
import { ConfigService } from '../config/config.js';
import { RedisModule, RedisService } from '../infrastructure/redis.module.js';
import { hash } from './tokens.js';

@Injectable()
export class OriginGuard implements CanActivate {
  constructor(private readonly config: ConfigService) {}
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<FastifyRequest>();
    if (['GET', 'HEAD', 'OPTIONS'].includes(request.method)) return true;
    if (!request.headers.origin || !this.config.settings.corsOrigins.includes(request.headers.origin)) throw new ForbiddenException();
    return true;
  }
}
@Injectable()
export class AuthRateGuard implements CanActivate {
  constructor(private readonly config: ConfigService, private readonly redis: RedisService) {}
  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<FastifyRequest>();
    const settings = this.config.settings;
    // Shared IP budget across all auth/profile routes. Never trust raw forwarding headers.
    const count = await this.redis.increment(`auth:rate:${hash(request.ip)}`, settings.authRateLimitWindowSeconds);
    if (count > settings.authRateLimitMax) {
      context.switchToHttp().getResponse<FastifyReply>().header('retry-after', settings.authRateLimitWindowSeconds);
      throw new HttpException('Too many requests', 429);
    }
    return true;
  }
}
@Module({ imports: [RedisModule], providers: [OriginGuard, AuthRateGuard], exports: [RedisModule, OriginGuard, AuthRateGuard] })
export class SecurityModule {}
