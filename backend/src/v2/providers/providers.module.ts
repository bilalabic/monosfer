import { Body, Controller, Get, Headers, Module, Param, Post, Query, Req, UseGuards } from '@nestjs/common';
import { ApiCookieAuth, ApiCreatedResponse, ApiHeader, ApiOkResponse, ApiTags } from '@nestjs/swagger';
import { AuthModule } from '../auth/auth.module.js';
import { PrivateDataModule } from '../private-data/private-data.module.js';
import { DeliveryAccessModule } from '../operations/access.js';
import { DatabaseModule } from '../infrastructure/database.module.js';
import { RedisModule } from '../infrastructure/redis.module.js';
import { DeliveryIdDto } from '../indexer/read.module.js';
import { SessionGuard, type AuthRequest } from '../security/session.guard.js';
import { AuthRateGuard, OriginGuard, SecurityModule } from '../security/security.module.js';
import { DevelopmentRouteProvider, EvidenceStorage, InAppNotificationProvider, LocalEvidenceStorage, NotificationProvider, RouteProvider } from './adapters.js';
import { EvidenceService, RouteService } from './providers.service.js';
import { ProviderJobs } from './jobs.js';
import { ProviderWorker } from './worker.js';
import { NotificationsService } from './notifications.service.js';
import { EvidenceContentDto, EvidenceInputDto, EvidenceResultDto, NotificationPageDto, NotificationQueryDto, RouteResultDto } from './providers.dto.js';
import { ApiProperty } from '@nestjs/swagger';
import { IsUUID } from 'class-validator';

class DeliveryEvidenceIdDto extends DeliveryIdDto { @ApiProperty({format:'uuid'}) @IsUUID() evidenceId!:string; }
@Controller('deliveries/:id') @ApiTags('providers') @ApiCookieAuth('session') @UseGuards(AuthRateGuard,SessionGuard,OriginGuard)
export class DeliveryProvidersController {
  constructor(private readonly routes:RouteService,private readonly evidence:EvidenceService){}
  @Get('route') @ApiOkResponse({type:RouteResultDto})
  route(@Param() params:DeliveryIdDto,@Req() req:AuthRequest){return this.routes.route(params.id,req.auth.user.walletAddress);}
  @Post('evidence') @ApiCreatedResponse({type:EvidenceResultDto}) @ApiHeader({name:'Idempotency-Key',required:true})
  @ApiHeader({name:'Origin',required:true}) @ApiHeader({name:'x-csrf-token',required:true})
  create(@Param() params:DeliveryIdDto,@Req() req:AuthRequest,@Headers('idempotency-key') key:string,@Body() input:EvidenceInputDto){return this.evidence.create(params.id,req.auth.user.walletAddress,key,input);}
  @Get('evidence/:evidenceId') @ApiOkResponse({type:EvidenceResultDto})
  metadata(@Param() params:DeliveryEvidenceIdDto,@Req() req:AuthRequest){return this.evidence.read(params.id,req.auth.user.walletAddress,params.evidenceId);}
  @Get('evidence/:evidenceId/content') @ApiOkResponse({type:EvidenceContentDto,description:'Owner-only JSON evidence content, never a public object URL'})
  content(@Param() params:DeliveryEvidenceIdDto,@Req() req:AuthRequest){return this.evidence.read(params.id,req.auth.user.walletAddress,params.evidenceId,true);}
}
@Controller('notifications') @ApiTags('notifications') @ApiCookieAuth('session') @UseGuards(AuthRateGuard,SessionGuard)
export class NotificationsController {
  constructor(private readonly notifications:NotificationsService){}
  @Get() @ApiOkResponse({type:NotificationPageDto,description:'Authorized in-app template inbox, bounded cursor pagination'})
  list(@Req() req:AuthRequest,@Query() query:NotificationQueryDto){return this.notifications.list(req.auth.user.walletAddress,query);}
}
@Module({imports:[DatabaseModule,RedisModule,DeliveryAccessModule,PrivateDataModule,AuthModule,SecurityModule],
  providers:[ProviderJobs,ProviderWorker,RouteService,EvidenceService,NotificationsService,
    {provide:RouteProvider,useClass:DevelopmentRouteProvider},{provide:EvidenceStorage,useClass:LocalEvidenceStorage},{provide:NotificationProvider,useClass:InAppNotificationProvider}],
  controllers:[DeliveryProvidersController,NotificationsController],exports:[ProviderWorker]})
export class ProvidersModule{}
