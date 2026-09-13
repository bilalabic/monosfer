import { MongoClient, ObjectId, type Db, type Document } from 'mongodb';
import { atPath, mapLegacy, mongoId, normalizeWallet, privatePaths, MappingError, type Collection } from './mapping.js';

export interface SourceItem { collection: Collection; document: Document; parent?: Document | null }
export interface LegacySettings { uri: string; database: string; readPreference: 'secondaryPreferred' | 'primary'; namespace: string }
export function parseLegacySettings(env: NodeJS.ProcessEnv): LegacySettings {
  const uri = env.LEGACY_MONGODB_URI ?? '';
  if (!/^mongodb(?:\+srv)?:\/\//.test(uri)) throw new Error('Invalid LEGACY_MONGODB_URI');
  const database = env.LEGACY_MONGODB_DATABASE ?? '';
  if (!/^[a-zA-Z0-9_-]{1,63}$/.test(database)) throw new Error('Invalid LEGACY_MONGODB_DATABASE');
  const namespace = env.LEGACY_MONGODB_SOURCE_ID ?? '';
  if (!/^[a-zA-Z0-9_-]{1,64}$/.test(namespace)) throw new Error('Invalid LEGACY_MONGODB_SOURCE_ID');
  const readPreference = env.LEGACY_MONGODB_READ_PREFERENCE ?? 'secondaryPreferred';
  if (!['secondaryPreferred', 'primary'].includes(readPreference)) throw new Error('Invalid LEGACY_MONGODB_READ_PREFERENCE');
  return { uri, database, namespace, readPreference: readPreference as LegacySettings['readPreference'] };
}
// Exposes only read operations. Never import Mongoose models: autoIndex could write to legacy Mongo.
export class LegacySource {
  readonly #client: MongoClient;
  readonly #db: Db;
  constructor(settings: LegacySettings) {
    try {
      this.#client = new MongoClient(settings.uri, { readPreference: settings.readPreference,
        serverSelectionTimeoutMS: 5000, connectTimeoutMS: 5000, socketTimeoutMS: 10000, maxPoolSize: 2, retryReads: false });
      this.#db = this.#client.db(settings.database);
    } catch { throw new Error('Invalid LEGACY_MONGODB_URI'); }
  }
  async close(): Promise<void> { await this.#client.close(); }
  async *items(): AsyncGenerator<SourceItem> {
    for (const collection of ['deliveries', 'disputes', 'users'] as const) {
      const projection = collection === 'users' ? { _id: 1, walletAddress: 1, 'courierProfile.location': 1,
        pushToken: 1, email: 1, phone: 1, name: 1, avatar: 1, createdAt: 1, updatedAt: 1 } : undefined;
      const cursor = this.#db.collection(collection).find({}, { batchSize: 100, maxTimeMS: 10000, projection }).sort({ _id: 1 });
      try {
        for await (const document of cursor) {
          let parent: Document | null | undefined;
          if (collection === 'disputes') {
            let parentId: string | null = null;
            try { parentId = mongoId(document.deliveryId); } catch { /* Mapper reports INVALID_ID without interpreting source text as a query. */ }
            parent = parentId ? await this.#db.collection('deliveries').findOne({ _id: new ObjectId(parentId) },
              { projection: { _id: 1, customer: 1, acceptedCourier: 1 }, maxTimeMS: 10000 }) : null;
          }
          yield { collection, document, parent };
        }
      } finally { await cursor.close(); }
    }
  }
  async inventory(): Promise<Record<string, unknown>> {
    const counts: Record<string, number> = {};
    for (const name of ['deliveries', 'disputes', 'users', 'bids', 'notifications', 'chainevents', 'courierstats', 'leaderboardsnapshots', 'badges']) {
      counts[name] = await this.#db.collection(name).countDocuments({}, { maxTimeMS: 10000 });
    }
    const fields: Record<string, number> = {};
    const detailPaths: Record<Collection, readonly string[]> = {
      deliveries: [...privatePaths.deliveries, 'pickup.address', 'pickup.lat', 'pickup.lng', 'pickup.contactPhone',
        'dropoff.address', 'dropoff.lat', 'dropoff.lng', 'dropoff.recipientName', 'dropoff.businessName', 'dropoff.contactPerson',
        'dropoff.orderRef', 'dropoff.department', 'dropoff.recipientNote', 'dropoff.recipientPhone', 'dropoff.recipientWallet', 'dropoff.deliveryCode'],
      disputes: privatePaths.disputes, users: privatePaths.users,
    };
    const classifications: Record<string, number> = {};
    const walletMatches = { matched: 0, missing: 0, invalid: 0 };
    for await (const item of this.items()) {
      for (const path of detailPaths[item.collection]) {
        const value = atPath(item.document, path);
        const key = `${item.collection}.${path}`;
        fields[key] ??= 0;
        if (value !== undefined && value !== null && value !== '') fields[key]++;
      }
      let status: string;
      try { status = mapLegacy(item.collection, item.document, item.parent) ? 'valid_private' : 'no_private'; }
      catch (error) { status = error instanceof MappingError ? error.code : 'INVALID_PAYLOAD'; }
      const key = `${item.collection}.${status}`;
      classifications[key] = (classifications[key] ?? 0) + 1;
      if (item.collection === 'deliveries') for (const value of [item.document.customer, item.document.acceptedCourier].filter(v => v != null)) {
        try {
          const wallet = normalizeWallet(value);
          // Wallet string is regex-validated before constructing an anchored case-insensitive match.
          const user = await this.#db.collection('users').findOne({ walletAddress: { $regex: `^${wallet}$`, $options: 'i' } }, { projection: { _id: 1 }, maxTimeMS: 10000 });
          walletMatches[user ? 'matched' : 'missing']++;
        } catch (error) {
          if (!(error instanceof MappingError)) throw error;
          walletMatches.invalid++;
        }
      }
    }
    return { counts, fieldPresence: fields, classifications, walletMatches, privateRisks: privatePaths,
      consistency: 'best_effort_non_snapshot', verification: 'legacy_unverified' };
  }
}

export function safeLegacyId(doc: Document): string | null {
  try { return mongoId(doc._id); } catch { return null; }
}
