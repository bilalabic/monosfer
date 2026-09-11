import { CanActivate, ExecutionContext, ForbiddenException, Injectable, ServiceUnavailableException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ConfigService } from '../config/config.js';
import { SessionGuard, type AuthRequest } from '../security/session.guard.js';
import { OriginGuard } from '../security/security.module.js';
import { AuditService, type AuditContext } from '../audit/audit.module.js';

@Injectable()
export class SupportPolicy {
  constructor(private readonly config: ConfigService) {}
  isAdmin(wallet: string) { return this.config.settings.release.adminWallets.includes(wallet.toLowerCase()); }
  allowed(wallet: string) { return this.isAdmin(wallet) || this.config.settings.release.supportWallets.includes(wallet.toLowerCase()); }
  authorize(wallet: string, admin = false) {
    if (!this.config.settings.release.supportEnabled) throw new ServiceUnavailableException();
    if (admin ? !this.isAdmin(wallet) : !this.allowed(wallet)) throw new ForbiddenException();
  }
}
@Injectable()
export class PrivilegedGuard implements CanActivate {
  constructor(private readonly sessions: SessionGuard, private readonly origins: OriginGuard,
    private readonly policy: SupportPolicy, private readonly audit: AuditService, private readonly reflector: Reflector) {}
  async canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest<AuthRequest>();
    const audit: AuditContext = { requestId: request.id, actor: null, action: 'privileged.guard', targetType: 'route', targetId: 'all' };
    try {
      await this.sessions.canActivate(context);
      audit.actor = request.auth.user.walletAddress;
      this.origins.canActivate(context);
      this.policy.authorize(audit.actor, this.reflector.getAllAndOverride<boolean>('adminOnly', [context.getHandler(), context.getClass()]) ?? false);
      return true;
    } catch (error) {
      audit.actor = request.auth?.user.walletAddress ?? null;
      await this.audit.failure(audit, error);
      throw error;
    }
  }
}
