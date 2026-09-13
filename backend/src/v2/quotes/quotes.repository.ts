import { Injectable, ForbiddenException, NotFoundException, ServiceUnavailableException, HttpException } from '@nestjs/common';
import type { PoolClient, QueryResultRow } from 'pg';
import { DatabaseService } from '../infrastructure/database.module.js';
import { ConfigService } from '../config/config.js';
import type { Envelope } from '../private-data/crypto.js';
import type { CoverageQuote } from './typed-data.js';

export interface Issuance extends QueryResultRow {
  digest: string; private_record_id: string; customer: string; stream: string; export_fingerprint: string;
  quote_bundle_fingerprint: string;
  signer: string; quote: CoverageQuote; expires_at: Date; refreshed_from: string | null;
}
@Injectable()
export class QuotesRepository {
  constructor(readonly db: DatabaseService, private readonly config: ConfigService) {}
  async transaction<T>(work: (client: PoolClient)=>Promise<T>): Promise<T> {
    try { return await this.db.transaction(work); }
    catch (error) { if (error instanceof HttpException) throw error; throw new ServiceUnavailableException(); }
  }
  async owned(client: Pick<PoolClient,'query'>, digest: string, customer: string): Promise<Issuance> {
    const row = (await client.query<Issuance>('SELECT * FROM monosfer.risk_quote_issuances WHERE digest=$1',[digest])).rows[0];
    if (!row) throw new NotFoundException();
    if (row.customer !== customer) throw new ForbiddenException();
    return row;
  }
  async trustedDelivery(client: Pick<PoolClient,'query'>, row: Issuance) {
    const s = this.config.settings.indexer;
    if (!s.enabled || row.stream !== `${s.chainId}:${s.deployment!.address.toLowerCase()}` || row.export_fingerprint !== s.fingerprint) return null;
    const result = await client.query(`SELECT d.delivery_id::text, l.private_record_id FROM monosfer.delivery_projections d
      JOIN monosfer.indexer_streams s ON s.stream=d.stream
      LEFT JOIN monosfer.private_delivery_links l ON l.stream=d.stream AND l.delivery_id=d.delivery_id
        AND l.quote_digest=$2 AND l.private_record_id=$6
      WHERE d.stream=$1 AND d.data->>'quoteDigest'=$2 AND d.data->>'customer'=$3
        AND s.status='ready' AND s.integrity_ok AND s.last_block=s.observed_head
        AND s.export_fingerprint=$4 AND s.checked_at>now()-($5::integer * interval '1 second')
      FOR SHARE OF s`, [row.stream,row.digest,row.customer,s.fingerprint,s.staleSeconds,row.private_record_id]);
    // Ambiguous projection must never grant private access.
    return result.rows.length===1 ? result.rows[0]! : null;
  }
}

export interface IdempotencyRow extends QueryResultRow {
  request_hash: string; encrypted_response: Envelope; expires_at: Date; quote_digest: string;
}
