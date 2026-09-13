import { ForbiddenException, Injectable, Module, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '../config/config.js';
import { DatabaseModule, DatabaseService } from '../infrastructure/database.module.js';
import { PrivateDataCrypto, recordAad, type Envelope, type RecordContext } from './crypto.js';

export interface TrustedDelivery {
  privateRecordId: string; customer: string; acceptedCourier: string | null;
  status: string; verification: 'confirmed';
}
// Links are established only by the server-side quote outbox worker, never legacy ID matching.
@Injectable()
export class PrivateDeliveryProjection {
  constructor(private readonly db: DatabaseService, private readonly config: ConfigService) {}
  async findConfirmed(recordId: string): Promise<TrustedDelivery | null> {
    const settings = this.config.settings.indexer;
    if (!settings.enabled || !/^[0-9a-f-]{36}$/i.test(recordId)) return null;
    const stream = `${settings.chainId}:${settings.deployment!.address.toLowerCase()}`;
    try {
      const result = await this.db.query(`SELECT d.data FROM monosfer.private_delivery_links l
        JOIN monosfer.delivery_projections d ON d.stream=l.stream AND d.delivery_id=l.delivery_id
        JOIN monosfer.indexer_streams s ON s.stream=l.stream
        JOIN monosfer.private_delivery_records p ON p.id=l.private_record_id
        WHERE l.private_record_id=$1 AND l.stream=$2 AND l.quote_digest=d.data->>'quoteDigest'
        AND p.customer_wallet=d.data->>'customer' AND s.status='ready' AND s.integrity_ok
        AND s.last_block=s.observed_head AND s.export_fingerprint=$4
        AND s.checked_at>now()-($3::integer * interval '1 second')`, [recordId, stream, settings.staleSeconds, settings.fingerprint]);
      const data = result.rows[0]?.data;
      return data ? { privateRecordId: recordId, customer: data.customer, acceptedCourier: data.courier, status: data.state, verification: 'confirmed' } : null;
    } catch { throw new ServiceUnavailableException(); }
  }
}
export function deliveryAccess(wallet: string, recordId: string, state: TrustedDelivery | null): 'customer' | 'courier' | null {
  if (!/^0x[0-9a-fA-F]{40}$/.test(wallet) || !state || state.verification !== 'confirmed' || state.privateRecordId !== recordId) return null;
  if (!['Bidding', 'AwaitingFunding', 'ReadyForPickup', 'InTransit', 'DeliveredPending', 'ReturnRequired', 'Completed', 'Returned', 'Cancelled', 'Expired'].includes(state.status)) return null;
  if (state.customer.toLowerCase() === wallet.toLowerCase()) return 'customer';
  if (state.acceptedCourier?.toLowerCase() === wallet.toLowerCase() && ['ReadyForPickup', 'InTransit'].includes(state.status)) return 'courier';
  return null;
}
export interface PrivateRecord extends RecordContext { encrypted_payload: Envelope }
@Injectable()
export class PrivateRecordsRepository {
  constructor(private readonly db: DatabaseService) {}
  async find(id: string): Promise<PrivateRecord | null> {
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) return null;
    try {
      const result = await this.db.query<PrivateRecord>('SELECT id, source_namespace, source_collection, legacy_mongo_id, kind, schema_version, encrypted_payload FROM monosfer.private_delivery_records WHERE id = $1', [id]);
      return result.rows[0] ?? null;
    } catch { throw new ServiceUnavailableException(); }
  }
}
@Injectable()
export class PrivateDataService {
  constructor(private readonly records: PrivateRecordsRepository, private readonly crypto: PrivateDataCrypto,
    private readonly projection: PrivateDeliveryProjection) {}
  // Called only with a wallet from authenticated server context; never take wallet/status from request body.
  async readDelivery(id: string, authenticatedWallet: string): Promise<Record<string, unknown>> {
    const access = deliveryAccess(authenticatedWallet, id, await this.projection.findConfirmed(id));
    if (!access) throw new ForbiddenException();
    const record = await this.records.find(id);
    if (!record || record.kind !== 'delivery') throw new ForbiddenException();
    let payload: Record<string, unknown>;
    try { payload = this.crypto.decrypt(record.encrypted_payload, recordAad(record)); }
    catch { throw new ServiceUnavailableException(); }
    if (access === 'customer') return payload;
    const select = (value: unknown, keys: string[]) => Object.fromEntries(keys
      .filter(key => value && typeof value === 'object' && key in value)
      .map(key => [key, (value as Record<string, unknown>)[key]]));
    return {
      pickup: select(payload.pickup, ['address', 'lat', 'lng', 'contactPhone']),
      dropoff: select(payload.dropoff, ['address', 'lat', 'lng', 'contactPhone', 'recipientType', 'recipientName', 'businessName', 'contactPerson', 'department', 'recipientNote', 'recipientPhone']),
    };
  }
}
@Module({ imports: [DatabaseModule], providers: [PrivateRecordsRepository, PrivateDeliveryProjection, PrivateDataService,
  { provide: PrivateDataCrypto, inject: [ConfigService], useFactory: (config: ConfigService) => new PrivateDataCrypto(config.settings) }],
  exports: [PrivateDataService] })
export class PrivateDataModule {}
