import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../infrastructure/database.module.js';
import { RedisService } from '../infrastructure/redis.module.js';
import { ConfigService } from '../config/config.js';
import { IndexerReadRepository } from '../indexer/read.module.js';
interface JobCounts {pending:string;failed:string;quotePending:string}

@Injectable()
export class OpsService {
  private requests=0;
  private failures=0;
  private traceFailures=0;
  constructor(private readonly db:DatabaseService,private readonly redis:RedisService,private readonly config:ConfigService,private readonly indexer:IndexerReadRepository) {}
  async observe(requestId:string,statusCode:number,duration:number) {
    this.requests++; if(statusCode>=500)this.failures++;
    if(Math.random()>=this.config.settings.release.traceSampleRate)return;
    try {
      await this.db.query(`INSERT INTO monosfer.ops_trace_events(request_id,event,status_code,duration_ms) VALUES($1,'http_response',$2,$3)`,
        [requestId,statusCode,Math.max(0,Math.min(2147483647,Math.round(duration)))]);
    } catch { this.traceFailures++; }
  }
  async status() {
    const [postgres,redis]=await Promise.all([this.db.ping(),this.redis.ping()]);
    let indexing: {status:string;lagBlocks?:string}={status:'error'};
    let jobs:JobCounts|null=null;
    let rebuild:unknown=null;
    let schemaReady=false;
    if(postgres) {
      try {
        indexing=(await this.indexer.read('status')).indexing;
        jobs=(await this.db.query<JobCounts>(`SELECT (SELECT count(*)::text FROM monosfer.provider_jobs WHERE status='pending') AS pending,
          (SELECT count(*)::text FROM monosfer.provider_jobs WHERE status='failed') AS failed,
          (SELECT count(*)::text FROM monosfer.transactional_outbox WHERE status='pending') AS "quotePending"`)).rows[0]??null;
        rebuild=(await this.db.query(`SELECT status,duration_ms,created_at FROM monosfer.ops_drill_runs WHERE kind='projection_rebuild' ORDER BY created_at DESC LIMIT 1`)).rows[0]??null;
        schemaReady=true;
      } catch { schemaReady=false; }
    }
    return {status:postgres&&redis&&schemaReady&&indexing.status==='ready'?'ready':'degraded',postgres,redis,schemaReady,indexer:indexing,jobs,rebuild,
      providers:{mode:'development',productionReady:false},http:{requests:this.requests,failures:this.failures,traceWriteFailures:this.traceFailures}};
  }
  async metrics() {
    const s=await this.status();
    const values: Record<string, number|string>={postgres_up:Number(s.postgres),redis_up:Number(s.redis),schema_ready:Number(s.schemaReady),
      indexer_ready:Number(s.indexer.status==='ready'),indexer_lag_blocks:s.indexer.lagBlocks??'0',
      worker_pending:s.jobs?.pending??'0',worker_failed:s.jobs?.failed??'0',quote_link_pending:s.jobs?.quotePending??'0',
      http_requests_total:this.requests,http_failures_total:this.failures,trace_write_failures_total:this.traceFailures};
    return Object.entries(values).map(([key,value])=>`# TYPE monosfer_${key} ${key.endsWith('_total')?'counter':'gauge'}\nmonosfer_${key} ${value}\n`).join('');
  }
}
