import { Controller, Get, Injectable, Module, NotFoundException, Param, Query, Res, ServiceUnavailableException } from '@nestjs/common';
import { ApiOkResponse, ApiProperty, ApiPropertyOptional, ApiResponse, ApiTags } from '@nestjs/swagger';
import { IsInt, IsOptional, Matches, Max, Min, ValidateBy } from 'class-validator';
import { Type } from 'class-transformer';
import type { FastifyReply } from 'fastify';
import type { PoolClient } from 'pg';
import { DatabaseModule, DatabaseService } from '../infrastructure/database.module.js';
import { ConfigService } from '../config/config.js';
import type { Cursor } from './store.js';
import { states } from './events.js';

function Uint256() { return ValidateBy({ name: 'uint256', validator: { validate: (value: unknown) =>
  typeof value === 'string' && /^(0|[1-9][0-9]{0,77})$/.test(value) && BigInt(value) < (1n << 256n) } }); }

export class IndexerStatusDto {
  @ApiProperty({ enum: ['disabled','indexing_pending','syncing','ready','stale','error'] }) status!: string;
  @ApiProperty() chainId!: number;
  @ApiPropertyOptional({ type: String }) indexedBlock?: string;
  @ApiPropertyOptional({ type: String }) finalizedBlock?: string;
  @ApiPropertyOptional({ type: String }) lagBlocks?: string;
  @ApiPropertyOptional({ type: String, nullable: true }) checkedAt?: string | null;
}
export class DeliveryIdDto { @ApiProperty({ pattern: '^(0|[1-9][0-9]{0,77})$' }) @Uint256() id!: string; }
export class DeliveryQueryDto {
  @ApiPropertyOptional({ minimum: 1, maximum: 100, default: 25 }) @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) limit = 25;
  @ApiPropertyOptional({ description: 'Exclusive decimal uint256 delivery ID cursor' }) @IsOptional() @Uint256() after?: string;
}
export class BidQueryDto {
  @ApiPropertyOptional({ minimum: 1, maximum: 100, default: 25 }) @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) limit = 25;
  @ApiPropertyOptional({ description: 'Exclusive lowercase courier address cursor' }) @IsOptional() @Matches(/^0x[0-9a-f]{40}$/) after?: string;
}
const decimalSchema = { type: 'string' as const, pattern: '^[0-9]+$', description: 'Exact decimal integer; timestamps are Unix seconds.' };
const deliverySchema = { type: 'object' as const, additionalProperties: false, properties: {
  ...Object.fromEntries(['id','riskTier','termsVersion','stateDeadline','courierAsk','protocolFee','returnReserve','requiredCollateral'].map(key => [key, decimalSchema])),
  customer: { type: 'string' as const, pattern: '^0x[0-9a-f]{40}$' }, courier: { type: 'string' as const, description: 'Zero address until selected.' },
  state: { type: 'string' as const, enum: states.slice(1) }, customerFunded: { type: 'boolean' as const }, courierFunded: { type: 'boolean' as const },
  quoteDigest: { type: 'string' as const }, creationTxHash: { type: 'string' as const },
} };
const bidSchema = { type: 'object' as const, additionalProperties: false, properties: {
  ...Object.fromEntries(['courierAsk','returnAsk','etaMinutes','validUntil','termsVersion'].map(key => [key, decimalSchema])),
  courier: { type: 'string' as const }, active: { type: 'boolean' as const, description: 'Reservation flag on-chain, not a guarantee the bid is still selectable.' },
} };
const projectionSchema = { type: 'object' as const, additionalProperties: false, required: ['indexing', 'data'], properties: {
  indexing: { $ref: '#/components/schemas/IndexerStatusDto' }, data: { ...deliverySchema, nullable: true },
} };
@Injectable()
export class IndexerReadRepository {
  readonly stream: string | null;
  constructor(private readonly database: DatabaseService, private readonly config: ConfigService) {
    const settings = config.settings.indexer;
    this.stream = settings.enabled ? `${settings.chainId}:${settings.deployment!.address.toLowerCase()}` : null;
  }
  private status(row?: Cursor): IndexerStatusDto {
    const settings = this.config.settings.indexer;
    if (!this.stream) return { status: 'disabled', chainId: settings.chainId };
    if (!row) return { status: 'indexing_pending', chainId: settings.chainId };
    const lag = BigInt(row.observed_head) > BigInt(row.last_block) ? BigInt(row.observed_head) - BigInt(row.last_block) : 0n;
    let status = row.status === 'error' || !row.integrity_ok || row.export_fingerprint !== settings.fingerprint ? 'error' : 'syncing';
    if (status !== 'error') {
      if (!row.checked_at) status = 'syncing';
      else if (Date.now() - row.checked_at.getTime() > settings.staleSeconds * 1000) status = 'stale';
      else if (lag > BigInt(settings.maxLag)) status = 'syncing';
      else if (row.status === 'ready') status = 'ready';
    }
    return { status, chainId: settings.chainId, indexedBlock: row.last_block, finalizedBlock: row.observed_head,
      lagBlocks: lag.toString(), checkedAt: row.checked_at?.toISOString() ?? null };
  }
  async read(kind: 'status' | 'list' | 'delivery' | 'bids', id?: string, limit = 25, after?: string): Promise<{ indexing: IndexerStatusDto; data: unknown; nextCursor?: string | null }> {
    if (!this.stream) return { indexing: this.status(), data: kind === 'list' || kind === 'bids' ? [] : null, ...(kind === 'list' || kind === 'bids' ? { nextCursor: null } : {}) };
    try {
      return await this.database.transaction(async db => {
        // Share-lock keeps cursor and projection response in the same committed view.
        const row = (await db.query<Cursor>('SELECT * FROM monosfer.indexer_streams WHERE stream=$1 FOR SHARE', [this.stream])).rows[0];
        const indexing = this.status(row);
        if (kind === 'status') return { indexing, data: null };
        if (kind === 'delivery') {
          const result = await db.query('SELECT data FROM monosfer.delivery_projections WHERE stream=$1 AND delivery_id=$2', [this.stream, id]);
          return { indexing, data: result.rows[0]?.data ?? null };
        }
        return this.page(db, indexing, kind, id, limit, after);
      });
    } catch { throw new ServiceUnavailableException(); }
  }
  private async page(db: PoolClient, indexing: IndexerStatusDto, kind: 'list' | 'bids', id: string | undefined, limit: number, after: string | undefined) {
    const result = kind === 'list'
      ? await db.query('SELECT data,delivery_id::text AS key FROM monosfer.delivery_projections WHERE stream=$1 AND ($2::numeric IS NULL OR delivery_id>$2) ORDER BY delivery_id LIMIT $3', [this.stream, after ?? null, limit + 1])
      : await db.query('SELECT data,courier AS key FROM monosfer.bid_projections WHERE stream=$1 AND delivery_id=$2 AND ($3::text IS NULL OR courier>$3) ORDER BY courier LIMIT $4', [this.stream, id, after ?? null, limit + 1]);
    return { indexing, data: result.rows.slice(0, limit).map(row => row.data), nextCursor: result.rows.length > limit ? result.rows[limit - 1]!.key as string : null };
  }
}
@ApiTags('indexer') @Controller('indexer')
export class IndexerStatusController {
  constructor(private readonly reads: IndexerReadRepository) {}
  @Get('status') @ApiOkResponse({ type: IndexerStatusDto })
  async status() { return (await this.reads.read('status')).indexing; }
}
@ApiTags('deliveries') @Controller('deliveries')
export class DeliveryReadController {
  constructor(private readonly reads: IndexerReadRepository) {}
  @Get() @ApiOkResponse({ schema: { ...projectionSchema, properties: { ...projectionSchema.properties, data: { type: 'array', items: deliverySchema }, nextCursor: { type: 'string', nullable: true } } } })
  list(@Query() query: DeliveryQueryDto) { return this.reads.read('list', undefined, query.limit, query.after); }
  @Get(':id') @ApiOkResponse({ schema: projectionSchema }) @ApiResponse({ status: 202, description: 'Indexer has not caught up; existence is not yet known.' })
  async detail(@Param() params: DeliveryIdDto, @Res({ passthrough: true }) reply: FastifyReply) {
    const result = await this.reads.read('delivery', params.id);
    if (result.data === null) {
      if (result.indexing.status === 'ready') throw new NotFoundException();
      reply.status(202);
    }
    return result;
  }
  @Get(':id/bids') @ApiOkResponse({ schema: { ...projectionSchema, properties: { ...projectionSchema.properties, data: { type: 'array', items: bidSchema }, nextCursor: { type: 'string', nullable: true } } } })
  bids(@Param() params: DeliveryIdDto, @Query() query: BidQueryDto) { return this.reads.read('bids', params.id, query.limit, query.after); }
}
@Module({ imports: [DatabaseModule], providers: [IndexerReadRepository], controllers: [IndexerStatusController, DeliveryReadController], exports: [IndexerReadRepository] })
export class IndexerReadModule {}
