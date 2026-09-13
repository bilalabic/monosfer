import type { Document } from 'mongodb';

export type Collection = 'deliveries' | 'disputes' | 'users';
export const privatePaths: Record<Collection, readonly string[]> = {
  deliveries: ['pickup', 'dropoff', 'notes', 'title', 'weight', 'ratingComment', 'timeline'],
  disputes: ['description', 'resolutionNote', 'evidence', 'jurors'],
  users: ['courierProfile.location', 'pushToken', 'email', 'phone', 'name', 'avatar'],
};
export const deliveryStates = ['OpenForBids', 'Accepted', 'InTransit', 'Delivered', 'Cancelled'] as const;
export interface MappedRecord {
  kind: 'delivery' | 'dispute' | 'courier_location';
  legacyId: string; parentLegacyId: string | null; customer: string | null; courier: string | null;
  status: string; metadata: Record<string, unknown>; payload: Record<string, unknown>;
}
export class MappingError extends Error {
  constructor(readonly code: 'INVALID_ID' | 'INVALID_WALLET' | 'INVALID_PAYLOAD' | 'INVALID_STATUS' | 'MISSING_PARENT') { super(code); }
}
export function mongoId(value: unknown): string {
  const id = typeof value === 'string' ? value : value && typeof value === 'object' && 'toHexString' in value && typeof value.toHexString === 'function' ? value.toHexString() as string : '';
  if (!/^[a-fA-F0-9]{24}$/.test(id)) throw new MappingError('INVALID_ID');
  return id.toLowerCase();
}
export function normalizeWallet(value: unknown): string {
  if (typeof value !== 'string' || !/^0x[a-fA-F0-9]{40}$/.test(value)) throw new MappingError('INVALID_WALLET');
  return value.toLowerCase();
}
export function atPath(doc: Document, path: string): unknown {
  return path.split('.').reduce<unknown>((value, key) => value && typeof value === 'object' ? (value as Document)[key] : undefined, doc);
}
function pick(doc: Document, fields: readonly string[]): Record<string, unknown> {
  return Object.fromEntries(fields.filter(key => doc[key] !== undefined).map(key => [key, doc[key]]));
}
function location(value: unknown, address = false): void {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new MappingError('INVALID_PAYLOAD');
  const v = value as Document;
  if (!Number.isFinite(v.lat) || Math.abs(v.lat) > 90 || !Number.isFinite(v.lng) || Math.abs(v.lng) > 180 ||
      (address && (typeof v.address !== 'string' || !v.address.trim()))) throw new MappingError('INVALID_PAYLOAD');
}
function metadata(doc: Document): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  const enums: Record<string, readonly string[]> = { network: ['monad-testnet', 'monad-mainnet', 'localhost'],
    packageType: ['document', 'food', 'small', 'medium', 'large'], urgency: ['standard', 'express', 'instant'] };
  for (const [key, values] of Object.entries(enums)) if (doc[key] !== undefined) {
    if (!values.includes(doc[key])) throw new MappingError('INVALID_PAYLOAD');
    result[key] = doc[key];
  }
  for (const key of ['maxBudget', 'acceptedAmount', 'escrowBalance', 'initiatorStake', 'respondentStake']) if (doc[key] !== undefined) {
    if (typeof doc[key] !== 'string' || !/^\d{1,78}$/.test(doc[key])) throw new MappingError('INVALID_PAYLOAD');
    result[key] = doc[key];
  }
  if (doc.onChainRequestId !== undefined) {
    if (!Number.isSafeInteger(doc.onChainRequestId) || doc.onChainRequestId < 0) throw new MappingError('INVALID_PAYLOAD');
    result.onChainRequestId = String(doc.onChainRequestId);
  }
  for (const key of ['creationTxHash', 'raiseTxHash', 'resolutionTxHash']) if (doc[key] !== undefined) {
    if (typeof doc[key] !== 'string' || !/^0x[0-9a-fA-F]{64}$/.test(doc[key])) throw new MappingError('INVALID_PAYLOAD');
    result[key] = doc[key].toLowerCase();
  }
  for (const key of ['createdAt', 'updatedAt', 'deadline', 'acceptedAt', 'pickedUpAt', 'deliveredAt', 'cancelledAt', 'ratedAt']) if (doc[key] !== undefined) {
    if (!(doc[key] instanceof Date) || !Number.isFinite(doc[key].getTime())) throw new MappingError('INVALID_PAYLOAD');
    result[key] = doc[key].toISOString();
  }
  if (doc.rating !== undefined) {
    if (typeof doc.rating !== 'number' || !Number.isFinite(doc.rating) || doc.rating < 1 || doc.rating > 5) throw new MappingError('INVALID_PAYLOAD');
    result.rating = doc.rating;
  }
  return result;
}
export function mapLegacy(collection: Collection, doc: Document, parent?: Document | null): MappedRecord | null {
  const legacyId = mongoId(doc._id);
  let result: MappedRecord;
  if (collection === 'deliveries') {
    const customer = normalizeWallet(doc.customer);
    const courier = doc.acceptedCourier ? normalizeWallet(doc.acceptedCourier) : null;
    if (!deliveryStates.includes(doc.status)) throw new MappingError('INVALID_STATUS');
    if (['Accepted', 'InTransit', 'Delivered'].includes(doc.status) && !courier) throw new MappingError('INVALID_WALLET');
    location(doc.pickup, true); location(doc.dropoff, true);
    result = { kind: 'delivery', legacyId, parentLegacyId: null, customer, courier, status: doc.status,
      metadata: metadata(doc), payload: pick(doc, privatePaths.deliveries) };
  } else if (collection === 'disputes') {
    const parentLegacyId = mongoId(doc.deliveryId);
    if (!parent || mongoId(parent._id) !== parentLegacyId) throw new MappingError('MISSING_PARENT');
    if (!['open', 'evidence_collection', 'jury_assigned', 'voting', 'resolved', 'cancelled'].includes(doc.status)) throw new MappingError('INVALID_STATUS');
    if (!Array.isArray(doc.evidence)) throw new MappingError('INVALID_PAYLOAD');
    for (const item of doc.evidence) {
      if (!item || !['text', 'image', 'video', 'gps_log'].includes(item.type)) throw new MappingError('INVALID_PAYLOAD');
      normalizeWallet(item.submitter);
      if (item.content !== undefined && typeof item.content !== 'string') throw new MappingError('INVALID_PAYLOAD');
      if (item.ipfsHash !== undefined && typeof item.ipfsHash !== 'string') throw new MappingError('INVALID_PAYLOAD');
    }
    result = { kind: 'dispute', legacyId, parentLegacyId, customer: normalizeWallet(parent.customer),
      courier: parent.acceptedCourier ? normalizeWallet(parent.acceptedCourier) : null, status: doc.status,
      metadata: metadata(doc), payload: pick(doc, [...privatePaths.disputes, 'initiator', 'respondent', 'reason']) };
  } else {
    const courier = normalizeWallet(doc.walletAddress);
    const loc = atPath(doc, 'courierProfile.location');
    // Email/phone and other user profile fields are inventoried, never imported here.
    if (loc === undefined && doc.pushToken === undefined) return null;
    if (loc !== undefined) location(loc);
    if (doc.pushToken !== undefined && typeof doc.pushToken !== 'string') throw new MappingError('INVALID_PAYLOAD');
    result = { kind: 'courier_location', legacyId, parentLegacyId: null, customer: null, courier,
      status: 'archived', metadata: metadata(pick(doc, ['createdAt', 'updatedAt'])),
      payload: { ...(loc !== undefined ? { location: loc } : {}), ...(doc.pushToken !== undefined ? { pushToken: doc.pushToken } : {}) } };
  }
  try { if (Buffer.byteLength(JSON.stringify(result.payload)) > 1048576) throw new Error(); }
  catch { throw new MappingError('INVALID_PAYLOAD'); }
  return result;
}
