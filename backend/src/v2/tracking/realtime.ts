import { Readable } from 'node:stream';
import { setTimeout as delay } from 'node:timers/promises';
import { randomUUID } from 'node:crypto';
import { Controller, Get, Headers, HttpException, Injectable, Module, Param, Req, Res, UseGuards, type BeforeApplicationShutdown } from '@nestjs/common';
import { ApiCookieAuth, ApiHeader, ApiProduces, ApiResponse, ApiTags } from '@nestjs/swagger';
import type { FastifyReply } from 'fastify';
import { AuthService } from '../auth/auth.service.js';
import { ConfigService } from '../config/config.js';
import { RedisService } from '../infrastructure/redis.module.js';
import { DeliveryIdDto } from '../indexer/read.module.js';
import { AuthRateGuard } from '../security/security.module.js';
import { SessionGuard, type AuthRequest } from '../security/session.guard.js';
import { cookieNames, hash } from '../security/tokens.js';
import { TrackingService } from './tracking.service.js';
import { TrackingCoreModule } from './tracking.module.js';

@Injectable()
export class TrackingRealtime implements BeforeApplicationShutdown {
  private readonly active=new Map<Readable,()=>Promise<void>>();
  private stopping=false;
  constructor(private readonly tracking:TrackingService,private readonly auth:AuthService,private readonly config:ConfigService,private readonly redis:RedisService){}
  async open(id:string,request:AuthRequest,raw:string,after?:string){
    const settings=this.config.settings.operations;
    if(this.stopping||this.active.size>=settings.maxConnections)throw new HttpException('Capacity reached',429);
    await this.tracking.read(id,request.auth,raw,after); // Status errors must precede SSE headers.
    const lease=`tracking:connection:${hash(raw)}`;const owner=randomUUID();
    const acquired=await this.redis.command(c=>c.set(lease,owner,{NX:true,EX:settings.streamSeconds+5}));
    if(!acquired)throw new HttpException('Connection exists',429);
    const stop=new AbortController();
    let released=false;let stream:Readable;
    const release=async()=>{if(released)return;released=true;stop.abort();clearTimeout(deadline);this.active.delete(stream);
      try{await this.redis.consume(lease,owner);}catch{/* bounded lease expires if Redis is unavailable */}};
    const generate=async function*(service:TrackingRealtime){
      let cursor=after;let hadLocation=false;
      try{
        while(!stop.signal.aborted){
          const context=await service.auth.authenticate(request.cookies[cookieNames(service.config.settings).session]);
          const batch=await service.tracking.read(id,context,raw,cursor);cursor=batch.cursor;
          if(stop.signal.aborted)return;
          if(batch.reset||(!batch.latest&&hadLocation))yield `event: reset\ndata: ${JSON.stringify(batch.latest??{location:null,eventId:null})}\n\n`;
          for(const event of batch.events){if(stop.signal.aborted)return;yield `id: ${event.eventId}\nevent: location\ndata: ${JSON.stringify(event)}\n\n`;}
          hadLocation=Boolean(batch.latest);
          yield ': heartbeat\n\n';
          await delay(settings.pollMs,undefined,{signal:stop.signal});
        }
      }catch{if(!stop.signal.aborted)yield 'event: closed\ndata: {"reason":"access_unavailable"}\n\n';}
      finally{await release();}
    };
    stream=Readable.from(generate(this),{objectMode:false,highWaterMark:1});
    const deadline=setTimeout(()=>stream.destroy(),settings.streamSeconds*1000);deadline.unref();
    stream.once('close',()=>{void release();});stream.on('error',()=>{});
    this.active.set(stream,async()=>{stream.destroy();await release();});
    if(this.stopping||this.active.size>settings.maxConnections){await this.active.get(stream)!();throw new HttpException('Capacity reached',429);}
    return stream;
  }
  async beforeApplicationShutdown(){this.stopping=true;await Promise.all([...this.active.values()].map(close=>close()));}
}
@Controller('deliveries/:id/tracking') @ApiTags('tracking-realtime') @ApiCookieAuth('session') @UseGuards(AuthRateGuard,SessionGuard)
export class TrackingRealtimeController {
  constructor(private readonly realtime:TrackingRealtime){}
  @Get('events') @ApiProduces('text/event-stream') @ApiHeader({name:'x-tracking-session',required:true})
  @ApiHeader({name:'Last-Event-ID',required:false}) @ApiResponse({status:200,description:'SSE location/reset/closed events and heartbeat comments. Fetch streaming with credentials and header token.'})
  async events(@Param() params:DeliveryIdDto,@Req() req:AuthRequest,@Headers('x-tracking-session') raw:string,@Headers('last-event-id') after:string|undefined,@Res() reply:FastifyReply){
    const stream=await this.realtime.open(params.id,req,raw,after);
    reply.raw.once('close',()=>stream.destroy());
    if(reply.raw.destroyed){stream.destroy();return;}
    return reply.type('text/event-stream').header('x-accel-buffering','no').send(stream);
  }
}
@Module({imports:[TrackingCoreModule],controllers:[TrackingRealtimeController],providers:[TrackingRealtime]})
export class TrackingRealtimeModule{}
