import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import type { FastifyRequest } from 'fastify';
import { AuthService, type AuthContext } from '../auth/auth.service.js';
import { ConfigService } from '../config/config.js';
import { cookieNames, equalToken } from './tokens.js';

export type AuthRequest = FastifyRequest & { auth: AuthContext };
@Injectable()
export class SessionGuard implements CanActivate {
  constructor(private readonly auth: AuthService, private readonly config: ConfigService) {}
  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AuthRequest>();
    request.auth = await this.auth.authenticate(request.cookies[cookieNames(this.config.settings).session]);
    if (!['GET', 'HEAD', 'OPTIONS'].includes(request.method) && !equalToken(request.headers['x-csrf-token'], request.auth.csrfToken)) throw new ForbiddenException();
    return true;
  }
}
