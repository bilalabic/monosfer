import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import type { PoolClient } from 'pg';
import { ConfigService } from '../config/config.js';
import { AuditService, type AuditContext, type AuditAction } from '../audit/audit.module.js';
import { PrivateDataCrypto, recordAad } from '../private-data/crypto.js';
import { EvidenceStorage, bounded, checksum } from '../providers/adapters.js';
import { idempotencyScope, privateHash } from '../quotes/idempotency.js';
import { SupportPolicy } from './policy.js';
import { trustedDelivery } from './trusted.js';
import type { CaseCreateDto, CasePatchDto, SupportPageDto, AuditPageDto } from './support.dto.js';

export interface SupportActor { wallet: string; requestId: string }
const caseColumns = 'id,stream,delivery_id::text,status,assignee,created_by,created_at,updated_at';
@Injectable()
export class SupportService {
  private readonly crypto: PrivateDataCrypto;
  constructor(private readonly config: ConfigService, private readonly audit: AuditService,
    private readonly policy: SupportPolicy, private readonly storage: EvidenceStorage) { this.crypto = new PrivateDataCrypto(config.settings); }
  context(actor: SupportActor, action: AuditAction, targetType: AuditContext['targetType'], targetId: string): AuditContext {
    return { requestId: actor.requestId, actor: actor.wallet.toLowerCase(), action, targetType, targetId };
  }
  run<T>(actor: SupportActor, action: AuditAction, type: AuditContext['targetType'], id: string, work: (client: PoolClient)=>Promise<T>, admin=false) {
    return this.audit.run(this.context(actor, action, type, id), async client => { this.policy.authorize(actor.wallet, admin); return work(client); });
  }
  private async assigned(client: PoolClient, actor: SupportActor, stream: string, id: string) {
    if (this.policy.isAdmin(actor.wallet)) return;
    const assigned = await client.query(`SELECT id FROM monosfer.support_cases WHERE stream=$1 AND delivery_id=$2
      AND assignee=$3 AND status IN ('open','investigating') FOR SHARE`, [stream,id,actor.wallet.toLowerCase()]);
    if (!assigned.rowCount) throw new ForbiddenException();
  }
  async delivery(actor: SupportActor, id: string, kind: 'summary'|'private'|'evidence'|'content', evidenceId?: string) {
    const action = {summary:'support.delivery',private:'support.private',evidence:'support.evidence',content:'support.content'} as const;
    return this.run(actor, action[kind], evidenceId?'evidence':'delivery', evidenceId??id, async client => {
      const {cursor,data,record,binding} = await trustedDelivery(client,this.config.settings,id,kind!=='summary');
      if (kind==='private' || kind==='content') await this.assigned(client,actor,cursor.stream,id);
      if (kind==='private') {
        const payload = this.crypto.decrypt(record!.encrypted_payload,recordAad(record!));
        // Explicit field allowlist excludes delivery codes, arbitrary notes, GPS history and legacy disputes.
        const select = (value: unknown) => Object.fromEntries(['address','lat','lng','contactPhone','recipientName','businessName','contactPerson','recipientPhone']
          .filter(key=>value && typeof value==='object' && key in value).map(key=>[key,(value as Record<string,unknown>)[key]]));
        return {privateRecordId:record!.id,pickup:select(payload.pickup),dropoff:select(payload.dropoff)};
      }
      if (kind==='content') {
        if (!this.config.settings.operations.enabled || this.config.settings.environment==='production') throw new ServiceUnavailableException();
        const row = (await client.query(`SELECT * FROM monosfer.evidence_packages WHERE id=$1 AND stream=$2 AND delivery_id=$3
          AND private_record_id=$4 AND binding=$5 FOR SHARE`,[evidenceId,cursor.stream,id,record!.id,binding])).rows[0];
        if (!row) throw new NotFoundException();
        if (row.status!=='ready') throw new ConflictException();
        const ciphertext = await bounded(this.config.settings.operations.providerTimeoutMs,signal=>this.storage.get(evidenceId!,signal));
        if (checksum(ciphertext)!==row.ciphertext_hash) throw new ServiceUnavailableException();
        const payload = this.crypto.decrypt(JSON.parse(ciphertext),`monosfer/evidence/v1/${evidenceId}/${binding}`);
        const bytes = payload.contentType==='text/plain' && typeof payload.text==='string' ? Buffer.from(payload.text) :
          typeof payload.contentBase64==='string' ? Buffer.from(payload.contentBase64,'base64') : null;
        if (!bytes || payload.contentType!==row.content_type || checksum(bytes)!==payload.evidenceHash) throw new ServiceUnavailableException();
        return Object.fromEntries(['contentType','text','contentBase64','gps','evidenceHash'].filter(k=>k in payload).map(k=>[k,payload[k]]));
      }
      const evidence = (await client.query(`SELECT id,content_type,status,created_at FROM monosfer.evidence_packages
        WHERE stream=$1 AND delivery_id=$2 AND binding=$3 ORDER BY created_at,id LIMIT 101`,[cursor.stream,id,binding])).rows;
      if (kind==='evidence') return {data:evidence.slice(0,100),hasMore:evidence.length>100};
      const quote = (await client.query(`SELECT digest,expires_at,created_at FROM monosfer.risk_quote_issuances WHERE digest=$1 AND stream=$2 AND customer=$3`,
        [data.quoteDigest,cursor.stream,data.customer])).rows[0] ?? null;
      const notifications = (await client.query(`SELECT count(*)::text AS total FROM monosfer.notifications WHERE stream=$1 AND delivery_id=$2 AND binding=$3`,[cursor.stream,id,binding])).rows[0];
      const dispute=(await client.query('SELECT data FROM monosfer.dispute_projections WHERE stream=$1 AND delivery_id=$2 AND updated_block<=$3 ORDER BY dispute_id DESC LIMIT 1',[cursor.stream,id,cursor.last_block])).rows[0]?.data??null;
      return {delivery:data,quote,privateRecordId:record?.id??null,evidence:evidence.slice(0,100),evidenceHasMore:evidence.length>100,notifications,dispute,committeeResolutionAlert:dispute?.committeeResolutionAlert??false};
    });
  }
  createCase(actor: SupportActor, input: CaseCreateDto, key: unknown) {
    return this.run(actor,'support.case.create','delivery',input.id,async client=>{
      const {cursor} = await trustedDelivery(client,this.config.settings,input.id,false);
      const normalized = {id:input.id,assignee:input.assignee?.toLowerCase()??null,note:input.note??null};
      if (normalized.assignee && !this.policy.allowed(normalized.assignee)) throw new BadRequestException();
      const scope = idempotencyScope(key,actor.wallet.toLowerCase(),'support.case',cursor.stream,this.config.settings.privateDataMasterKeyB64);
      const requestHash = privateHash(normalized,this.config.settings.privateDataMasterKeyB64);
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[scope]);
      const previous = (await client.query(`SELECT creation_response,request_hash FROM monosfer.support_cases WHERE scope_hash=$1 AND idempotency_expires_at>now()`,[scope])).rows[0];
      if (previous) { if(previous.request_hash!==requestHash) throw new ConflictException(); return previous.creation_response; }
      const id=randomUUID();
      const note=normalized.note===null?null:this.crypto.encrypt({note:normalized.note},`monosfer/support-note/v1/${id}`);
      const row=(await client.query(`INSERT INTO monosfer.support_cases(id,stream,delivery_id,assignee,created_by,scope_hash,request_hash,idempotency_expires_at,encrypted_note)
        VALUES($1,$2,$3,$4,$5,$6,$7,now()+$8::integer*interval '1 second',$9) RETURNING ${caseColumns}`,
        [id,cursor.stream,input.id,normalized.assignee,actor.wallet.toLowerCase(),scope,requestHash,this.config.settings.release.caseIdempotencyTtl,note])).rows[0];
      await client.query(`INSERT INTO monosfer.support_case_events(case_id,actor_wallet,action,status,assignee,encrypted_note) VALUES($1,$2,'created','open',$3,$4)`,[id,actor.wallet.toLowerCase(),normalized.assignee,note]);
      await client.query('UPDATE monosfer.support_cases SET creation_response=$2 WHERE id=$1',[id,JSON.stringify(row)]);
      return row;
    });
  }
  listCases(actor: SupportActor, query: SupportPageDto) {
    return this.run(actor,'support.case.list','case','all',async client=>{
      const rows=(await client.query(`SELECT ${caseColumns} FROM monosfer.support_cases WHERE ($1::uuid IS NULL OR id>$1) ORDER BY id LIMIT $2`,[query.after??null,query.limit+1])).rows;
      return {data:rows.slice(0,query.limit),nextCursor:rows.length>query.limit?rows[query.limit-1]!.id:null};
    });
  }
  readCase(actor: SupportActor, id: string) {
    return this.run(actor,'support.case.read','case',id,async client=>{
      const row=(await client.query(`SELECT ${caseColumns} FROM monosfer.support_cases WHERE id=$1`,[id])).rows[0];
      if(!row) throw new NotFoundException();
      // Case history exposes transition metadata; encrypted free-text is not a general support read surface.
      const events=(await client.query(`SELECT id,actor_wallet,action,status,assignee,created_at FROM monosfer.support_case_events WHERE case_id=$1 ORDER BY id DESC LIMIT 100`,[id])).rows;
      return {...row,events};
    });
  }
  patchCase(actor: SupportActor,id: string,input: CasePatchDto) {
    return this.run(actor,'support.case.update','case',id,async client=>{
      if(!Object.keys(input).length) throw new BadRequestException();
      const row=(await client.query('SELECT * FROM monosfer.support_cases WHERE id=$1 FOR UPDATE',[id])).rows[0];
      if(!row) throw new NotFoundException();
      const assignee=input.assignee===undefined?row.assignee:input.assignee?.toLowerCase()??null;
      if(assignee && !this.policy.allowed(assignee)) throw new BadRequestException();
      const note=input.note===undefined?row.encrypted_note:this.crypto.encrypt({note:input.note},`monosfer/support-note/v1/${id}`);
      const status=input.status??row.status;
      const result=(await client.query(`UPDATE monosfer.support_cases SET status=$2,assignee=$3,encrypted_note=$4,updated_at=now() WHERE id=$1 RETURNING ${caseColumns}`,[id,status,assignee,note])).rows[0];
      await client.query(`INSERT INTO monosfer.support_case_events(case_id,actor_wallet,action,status,assignee,encrypted_note) VALUES($1,$2,'updated',$3,$4,$5)`,[id,actor.wallet.toLowerCase(),status,assignee,input.note===undefined?null:note]);
      return result;
    });
  }
  listAudit(actor: SupportActor,query: AuditPageDto) {
    return this.run(actor,'admin.audit','audit','all',async client=>{
      const rows=(await client.query(`SELECT id,request_id,actor_wallet,action,target_type,target_id,decision,reason_code,created_at FROM monosfer.privileged_audit_log
        WHERE id>$1::bigint ORDER BY id LIMIT $2`,[query.after??'0',query.limit+1])).rows;
      return {data:rows.slice(0,query.limit),nextCursor:rows.length>query.limit?rows[query.limit-1]!.id:null};
    },true);
  }
}
