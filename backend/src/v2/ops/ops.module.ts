import { CanActivate, Controller, ExecutionContext, ForbiddenException, Get, Injectable, Module, Param, Req, Res, UnauthorizedException, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiCookieAuth, ApiOkResponse, ApiProduces, ApiTags } from '@nestjs/swagger';
import { createHash, timingSafeEqual } from 'node:crypto';
import type { FastifyReply } from 'fastify';
import { ConfigService } from '../config/config.js';
import { DatabaseModule } from '../infrastructure/database.module.js';
import { RedisModule } from '../infrastructure/redis.module.js';
import { IndexerReadModule } from '../indexer/read.module.js';
import { SessionGuard, type AuthRequest } from '../security/session.guard.js';
import { SupportModule } from '../support/support.module.js';
import { SupportPolicy } from '../support/policy.js';
import { AuditService } from '../audit/audit.module.js';
import { TraceIdDto } from '../support/support.dto.js';
import { OpsService } from './ops.service.js';
import { tracesSchema } from '../support/support.schemas.js';

export function validOpsToken(header:unknown,expected:string) {
  if(!expected || typeof header!=='string' || !header.startsWith('Bearer ') || header.length>263)return false;
  return timingSafeEqual(createHash('sha256').update(header.slice(7)).digest(),createHash('sha256').update(expected).digest());
}
@Injectable()
export class OpsTokenGuard implements CanActivate {
  constructor(private readonly config:ConfigService) {}
  canActivate(ctx:ExecutionContext) {
    if(!validOpsToken(ctx.switchToHttp().getRequest<AuthRequest>().headers.authorization,this.config.settings.release.metricsToken))throw new UnauthorizedException();
    return true;
  }
}
@Injectable()
export class OpsTraceGuard implements CanActivate {
  constructor(private readonly config:ConfigService,private readonly sessions:SessionGuard,private readonly policy:SupportPolicy,private readonly audit:AuditService) {}
  async canActivate(ctx:ExecutionContext) {
    const req=ctx.switchToHttp().getRequest<AuthRequest>();
    try {
      if(validOpsToken(req.headers.authorization,this.config.settings.release.metricsToken))return true;
      await this.sessions.canActivate(ctx);
      if(!this.policy.isAdmin(req.auth.user.walletAddress))throw new ForbiddenException();
      return true;
    } catch(error) {
      await this.audit.failure({requestId:req.id,actor:req.auth?.user.walletAddress??null,action:'ops.traces',targetType:'trace',targetId:'all'},error);
      throw error;
    }
  }
}
@Controller('ops') @ApiTags('ops')
export class OpsController {
  constructor(private readonly ops:OpsService,private readonly audit:AuditService) {}
  @Get('status') @ApiBearerAuth('ops') @UseGuards(OpsTokenGuard)
  @ApiOkResponse({schema:{type:'object',properties:{status:{type:'string',enum:['ready','degraded']},postgres:{type:'boolean'},redis:{type:'boolean'},schemaReady:{type:'boolean'},indexer:{type:'object'},jobs:{type:'object',nullable:true},rebuild:{type:'object',nullable:true},providers:{type:'object'},http:{type:'object'}}}})
  status() {return this.ops.status();}
  @Get('metrics') @ApiBearerAuth('ops') @ApiProduces('text/plain') @UseGuards(OpsTokenGuard)
  @ApiOkResponse({schema:{type:'string'}})
  async metrics(@Res({passthrough:true})reply:FastifyReply) {reply.type('text/plain; version=0.0.4; charset=utf-8');return this.ops.metrics();}
  @Get('traces/:requestId') @ApiBearerAuth('ops') @ApiCookieAuth('session') @UseGuards(OpsTraceGuard)
  @ApiOkResponse({schema:tracesSchema})
  traces(@Req()req:AuthRequest,@Param()p:TraceIdDto) {
    return this.audit.run({requestId:req.id,actor:req.auth?.user.walletAddress??null,action:'ops.traces',targetType:'trace',targetId:p.requestId},async client=>({
      data:(await client.query(`SELECT request_id,event,status_code,duration_ms,created_at FROM monosfer.ops_trace_events WHERE request_id=$1 ORDER BY id LIMIT 100`,[p.requestId])).rows
    }));
  }
}
@Module({imports:[DatabaseModule,RedisModule,IndexerReadModule,SupportModule],providers:[OpsService,OpsTokenGuard,OpsTraceGuard],controllers:[OpsController],exports:[OpsService]})
export class OpsModule {}
