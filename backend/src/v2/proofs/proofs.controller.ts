import { Body, Controller, Headers, Param, Post, Req, UseGuards } from '@nestjs/common';
import { ApiCookieAuth, ApiCreatedResponse, ApiHeader, ApiTags } from '@nestjs/swagger';
import { AuthRateGuard, OriginGuard } from '../security/security.module.js';
import { SessionGuard, type AuthRequest } from '../security/session.guard.js';
import { DeliveryIdDto } from '../indexer/read.module.js';
import { AcceptanceInputDto, AcceptanceResponseDto, PodInputDto, PodResponseDto } from './proofs.dto.js';
import { ProofsService } from './proofs.service.js';
@Controller('deliveries') @ApiTags('proofs') @ApiCookieAuth('session')
@UseGuards(AuthRateGuard,SessionGuard,OriginGuard)
@ApiHeader({name:'Idempotency-Key',required:true}) @ApiHeader({name:'x-csrf-token',required:true}) @ApiHeader({name:'Origin',required:true})
export class ProofsController {
  constructor(private readonly proofs:ProofsService){}
  @Post(':id/pickup-acceptances') @ApiCreatedResponse({type:AcceptanceResponseDto})
  pickup(@Req() r:AuthRequest,@Param() p:DeliveryIdDto,@Headers('idempotency-key') key:string,@Body() body:AcceptanceInputDto){return this.proofs.issue('pickup',p.id,r.auth.user.walletAddress,key,body);}
  @Post(':id/return-acceptances') @ApiCreatedResponse({type:AcceptanceResponseDto})
  returns(@Req() r:AuthRequest,@Param() p:DeliveryIdDto,@Headers('idempotency-key') key:string,@Body() body:AcceptanceInputDto){return this.proofs.issue('return',p.id,r.auth.user.walletAddress,key,body);}
  @Post(':id/pod-attestations') @ApiCreatedResponse({type:PodResponseDto})
  pod(@Req() r:AuthRequest,@Param() p:DeliveryIdDto,@Headers('idempotency-key') key:string,@Body() body:PodInputDto){return this.proofs.issue('pod',p.id,r.auth.user.walletAddress,key,body);}
}
