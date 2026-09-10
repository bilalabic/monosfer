import { Body, Controller, Delete, Get, Headers, HttpCode, Module, Param, Post, Req, UseGuards } from '@nestjs/common';
import { ApiCookieAuth, ApiCreatedResponse, ApiHeader, ApiOkResponse, ApiTags } from '@nestjs/swagger';
import { AuthModule } from '../auth/auth.module.js';
import { DeliveryIdDto } from '../indexer/read.module.js';
import { RedisModule } from '../infrastructure/redis.module.js';
import { DeliveryAccessModule } from '../operations/access.js';
import { AuthRateGuard, OriginGuard, SecurityModule } from '../security/security.module.js';
import { SessionGuard, type AuthRequest } from '../security/session.guard.js';
import { TrackingEmptyDto, TrackingLatestDto, TrackingLocationDto, TrackingPublishedDto, TrackingSessionDto } from './tracking.dto.js';
import { TrackingService } from './tracking.service.js';
import { TrackingStore } from './store.js';

@Module({imports:[RedisModule,DeliveryAccessModule,AuthModule,SecurityModule],providers:[TrackingService,TrackingStore],exports:[TrackingService,AuthModule,SecurityModule]})
export class TrackingCoreModule{}
@Controller('deliveries/:id/tracking') @ApiTags('tracking') @ApiCookieAuth('session') @UseGuards(AuthRateGuard,SessionGuard,OriginGuard)
export class TrackingController {
  constructor(private readonly tracking:TrackingService){}
  @Post('sessions') @ApiCreatedResponse({type:TrackingSessionDto}) @ApiHeader({name:'Origin',required:true}) @ApiHeader({name:'x-csrf-token',required:true})
  create(@Param() params:DeliveryIdDto,@Req() req:AuthRequest,@Body() _body:TrackingEmptyDto){return this.tracking.create(params.id,req.auth);}
  @Delete('sessions') @HttpCode(204) @ApiHeader({name:'x-tracking-session',required:true}) @ApiHeader({name:'Origin',required:true}) @ApiHeader({name:'x-csrf-token',required:true})
  revoke(@Param() params:DeliveryIdDto,@Req() req:AuthRequest,@Headers('x-tracking-session') raw:string){return this.tracking.revoke(params.id,req.auth,raw);}
  @Post('location') @ApiCreatedResponse({type:TrackingPublishedDto}) @ApiHeader({name:'x-tracking-session',required:true}) @ApiHeader({name:'Origin',required:true}) @ApiHeader({name:'x-csrf-token',required:true})
  publish(@Param() params:DeliveryIdDto,@Req() req:AuthRequest,@Headers('x-tracking-session') raw:string,@Body() input:TrackingLocationDto){return this.tracking.publish(params.id,req.auth,raw,input);}
  @Get('location') @ApiOkResponse({type:TrackingLatestDto}) @ApiHeader({name:'x-tracking-session',required:true})
  async latest(@Param() params:DeliveryIdDto,@Req() req:AuthRequest,@Headers('x-tracking-session') raw:string){return (await this.tracking.read(params.id,req.auth,raw)).latest??{location:null,eventId:null};}
}
@Module({imports:[TrackingCoreModule],controllers:[TrackingController]})
export class TrackingApiModule{}
