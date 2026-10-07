import { Controller, Get, Injectable, Module, NotFoundException } from '@nestjs/common';
import { ConfigService } from '../config/config.js';
import { DatabaseModule, DatabaseService } from '../infrastructure/database.module.js';
import { supportsQuoteNetwork } from '../quotes/config.js';

@Injectable()
export class DevelopmentDatasetService {
  constructor(private readonly config: ConfigService, private readonly database: DatabaseService) {}
  async read() {
    const s = this.config.settings;
    if (s.indexer.chainId !== 31337 || !s.indexer.enabled ||
      !supportsQuoteNetwork(s.environment, s.indexer.chainId, s.indexer.rpcUrl)) throw new NotFoundException();
    const stream = `${s.indexer.chainId}:${s.indexer.deployment!.address.toLowerCase()}`;
    const row = (await this.database.query('SELECT data FROM monosfer.development_datasets WHERE stream=$1', [stream])).rows[0];
    const data = row?.data ?? { deliveries: [], couriers: [] };
    // Deliberate allowlist: fixture metadata must never expose contact details,
    // private payloads, account keys, or signatures, even if the DB contains them.
    const pick = (item: Record<string, unknown>, keys: string[]) => Object.fromEntries(keys.map(key => [key, item[key]]));
    return {
      deliveries: data.deliveries.map((item: Record<string, unknown>) => pick(item, ['id', 'title', 'pickupArea', 'dropoffArea', 'distance', 'weight', 'description', 'budget', 'createdAt'])),
      couriers: data.couriers.map((item: Record<string, unknown>) => pick(item, ['walletAddress', 'name', 'vehicleType', 'joinedDate'])),
    };
  }
}
@Controller('development')
export class DevelopmentDatasetController {
  constructor(private readonly dataset: DevelopmentDatasetService) {}
  @Get('dataset') read() { return this.dataset.read(); }
}
@Module({ imports: [DatabaseModule], providers: [DevelopmentDatasetService], controllers: [DevelopmentDatasetController] })
export class DevelopmentModule {}
