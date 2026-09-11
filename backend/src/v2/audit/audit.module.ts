import { HttpException, Injectable, Module, ServiceUnavailableException } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { DatabaseModule, DatabaseService } from '../infrastructure/database.module.js';

export type AuditAction = 'support.delivery'|'support.private'|'support.evidence'|'support.content'|'support.case.create'|'support.case.list'|'support.case.read'|'support.case.update'|'support.reputation'|'admin.audit'|'ops.traces'|'privileged.guard';
export interface AuditContext { requestId: string; actor: string | null; action: AuditAction; targetType: 'delivery'|'evidence'|'case'|'wallet'|'audit'|'trace'|'route'; targetId: string }
type Decision = 'allowed'|'denied'|'failed';
type Reason = 'AUTHORIZED'|'ACCESS_DENIED'|'UNAUTHENTICATED'|'UNAVAILABLE'|'INVALID_REQUEST'|'CONFLICT'|'NOT_FOUND';
export function safeTarget(value: unknown): string {
  return typeof value === 'string' && /^(?:[0-9]{1,78}|[0-9a-f-]{36}|0x[0-9a-fA-F]{40}|all)$/.test(value) ? value.toLowerCase() : 'invalid';
}
@Injectable()
export class AuditService {
  constructor(private readonly db: DatabaseService) {}
  async append(context: AuditContext, decision: Decision, reason: Reason, client?: PoolClient) {
    try {
      const sql = `INSERT INTO monosfer.privileged_audit_log(request_id,actor_wallet,action,target_type,target_id,decision,reason_code) VALUES($1,$2,$3,$4,$5,$6,$7)`;
      const parameters = [context.requestId, context.actor?.toLowerCase() ?? null, context.action, context.targetType, safeTarget(context.targetId), decision, reason];
      if (client) await client.query(sql, parameters); else await this.db.query(sql, parameters);
    } catch { throw new ServiceUnavailableException(); }
  }
  async failure(context: AuditContext, error: unknown) {
    const status = error instanceof HttpException ? error.getStatus() : 503;
    const reason: Reason = status===401?'UNAUTHENTICATED':status===403?'ACCESS_DENIED':status===400?'INVALID_REQUEST':status===404?'NOT_FOUND':status===409?'CONFLICT':'UNAVAILABLE';
    await this.append(context, status >= 500 ? 'failed' : 'denied', reason);
  }
  // Result is not released until the durable audit write commits. Failure rolls back the work.
  async run<T>(context: AuditContext, work: (client: PoolClient) => Promise<T>): Promise<T> {
    try {
      return await this.db.transaction(async client => {
        const result = await work(client);
        await this.append(context, 'allowed', 'AUTHORIZED', client);
        return result;
      });
    } catch (error) {
      await this.failure(context, error);
      if (error instanceof HttpException) throw error;
      throw new ServiceUnavailableException();
    }
  }
}
@Module({ imports: [DatabaseModule], providers: [AuditService], exports: [AuditService] })
export class AuditModule {}
