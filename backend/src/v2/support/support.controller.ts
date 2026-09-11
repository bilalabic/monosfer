import { Body, Controller, Get, Headers, Param, Patch, Post, Query, Req, SetMetadata, UseGuards } from '@nestjs/common';
import { ApiCookieAuth, ApiCreatedResponse, ApiHeader, ApiOkResponse, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AuthRateGuard } from '../security/security.module.js';
import type { AuthRequest } from '../security/session.guard.js';
import { DeliveryIdDto } from '../indexer/read.module.js';
import { PrivilegedGuard } from './policy.js';
import { SupportService } from './support.service.js';
import { AuditPageDto, CaseCreateDto, CaseIdDto, CasePatchDto, SupportEvidenceIdDto, SupportPageDto } from './support.dto.js';
import { auditPageSchema, caseDetailSchema, casePageSchema, caseSchema, evidencePageSchema, supportPrivateSchema } from './support.schemas.js';
import { EvidenceContentDto } from '../providers/providers.dto.js';

export const supportActor = (req: AuthRequest) => ({wallet:req.auth.user.walletAddress,requestId:req.id});
@Controller('support') @ApiTags('support') @ApiCookieAuth('session') @UseGuards(AuthRateGuard,PrivilegedGuard)
export class SupportController {
  constructor(private readonly support: SupportService) {}
  @Get('deliveries/:id') @ApiOperation({summary:'Audited finalized delivery summary'})
  @ApiOkResponse({schema:{type:'object',properties:{delivery:{type:'object'},quote:{type:'object',nullable:true,properties:{digest:{type:'string'},expires_at:{type:'string',format:'date-time'},created_at:{type:'string',format:'date-time'}}},privateRecordId:{type:'string',format:'uuid',nullable:true},evidence:evidencePageSchema.properties.data,evidenceHasMore:{type:'boolean'},notifications:{type:'object',properties:{total:{type:'string'}}}}}})
  delivery(@Req() req:AuthRequest,@Param() p:DeliveryIdDto) { return this.support.delivery(supportActor(req),p.id,'summary'); }
  @Get('deliveries/:id/private') @ApiOperation({summary:'Audited restricted private fields; admin or active assigned case required'})
  @ApiOkResponse({schema:supportPrivateSchema})
  private(@Req() req:AuthRequest,@Param() p:DeliveryIdDto) { return this.support.delivery(supportActor(req),p.id,'private'); }
  @Get('deliveries/:id/evidence') @ApiOkResponse({schema:evidencePageSchema})
  evidence(@Req() req:AuthRequest,@Param() p:DeliveryIdDto) { return this.support.delivery(supportActor(req),p.id,'evidence'); }
  @Get('deliveries/:id/evidence/:evidenceId/content') @ApiOkResponse({type:EvidenceContentDto})
  content(@Req() req:AuthRequest,@Param() p:SupportEvidenceIdDto) { return this.support.delivery(supportActor(req),p.id,'content',p.evidenceId); }
  @Post('cases') @ApiHeader({name:'Idempotency-Key',required:true}) @ApiHeader({name:'Origin',required:true}) @ApiHeader({name:'x-csrf-token',required:true})
  @ApiCreatedResponse({schema:caseSchema})
  create(@Req() req:AuthRequest,@Headers('idempotency-key') key:string,@Body() body:CaseCreateDto) { return this.support.createCase(supportActor(req),body,key); }
  @Get('cases') @ApiOkResponse({schema:casePageSchema})
  cases(@Req() req:AuthRequest,@Query() query:SupportPageDto) { return this.support.listCases(supportActor(req),query); }
  @Get('cases/:caseId') @ApiOkResponse({schema:caseDetailSchema})
  case(@Req() req:AuthRequest,@Param() p:CaseIdDto) { return this.support.readCase(supportActor(req),p.caseId); }
  @Patch('cases/:caseId') @ApiHeader({name:'Origin',required:true}) @ApiHeader({name:'x-csrf-token',required:true})
  @ApiOkResponse({schema:caseSchema})
  update(@Req() req:AuthRequest,@Param() p:CaseIdDto,@Body() body:CasePatchDto) { return this.support.patchCase(supportActor(req),p.caseId,body); }
}
@Controller('admin') @ApiTags('admin') @ApiCookieAuth('session') @UseGuards(AuthRateGuard,PrivilegedGuard) @SetMetadata('adminOnly',true)
export class AdminAuditController {
  constructor(private readonly support: SupportService) {}
  @Get('audit') @ApiOkResponse({schema:auditPageSchema})
  audit(@Req() req:AuthRequest,@Query() query:AuditPageDto) { return this.support.listAudit(supportActor(req),query); }
}
