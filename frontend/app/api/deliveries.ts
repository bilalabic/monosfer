import { api, createIdempotencyKey } from './client'

export type IndexerState = 'disabled' | 'indexing_pending' | 'syncing' | 'ready' | 'stale' | 'error'
export type ChainDeliveryState =
  | 'Bidding' | 'AwaitingFunding' | 'ReadyForPickup' | 'InTransit' | 'DeliveredPending'
  | 'ReturnRequired' | 'Disputed' | 'Completed' | 'Returned' | 'Resolved' | 'Cancelled' | 'Expired'

export interface IndexerStatus {
  status: IndexerState
  chainId: number
  indexedBlock?: string
  finalizedBlock?: string
  lagBlocks?: string
  checkedAt?: string | null
}

export interface ChainDelivery {
  id: string
  customer: string
  courier: string
  state: ChainDeliveryState
  riskTier: string
  termsVersion: string
  stateDeadline: string
  etaDeadline: string
  etaMinutes: string
  completedAt: string
  courierAsk: string
  protocolFee: string
  returnReserve: string
  requiredCollateral: string
  customerFunded: boolean
  courierFunded: boolean
  quoteDigest: string
  creationTxHash: string
}

export interface ChainBid {
  courier: string
  courierAsk: string
  returnAsk: string
  etaMinutes: string
  validUntil: string
  termsVersion: string
  active: boolean
}

export interface Projection<T> {
  indexing: IndexerStatus
  data: T
  nextCursor?: string | null
}

export interface TypedDataPayload {
  domain: Record<string, unknown>
  types: Record<string, readonly { name: string; type: string }[]>
  primaryType: string
  message: Record<string, unknown>
}

export interface AcceptanceResponse {
  acceptance: Record<string, string>
  typedData: TypedDataPayload
  digest: string
  expiresAt: string
  status: 'issued'
}

export interface PodResponse {
  attestation: Record<string, string>
  typedData: TypedDataPayload
  digest: string
  signature: `0x${string}`
  expiresAt: string
  status: 'issued'
}

export interface QuoteResponse {
  privateRecordId: string
  quoteDigest: `0x${string}`
  quote: {
    customer: `0x${string}`
    riskTier: number
    declaredValue: string
    requiredCoverage: string
    issuedAt: string
    expiresAt: string
    salt: `0x${string}`
  }
  signature: `0x${string}`
  typedData: TypedDataPayload
  expiresAt: string
  status: 'issued'
}

export interface QuoteStatus {
  quoteDigest: string
  privateRecordId: string
  expiresAt: string
  status: 'issued' | 'expired' | 'refreshed' | 'redeemed' | 'linked'
  deliveryId: string | null
}

export interface CreateQuoteInput {
  declaredValue: string
  metadata: { packageType: 'document' | 'food' | 'small' | 'medium' | 'large'; urgency: 'standard' | 'express' | 'instant' }
  privatePayload: {
    pickup: { address: string; lat: number; lng: number; contactPhone?: string }
    dropoff: {
      address: string; lat: number; lng: number; recipientName?: string; businessName?: string
      contactPerson?: string; department?: string; recipientPhone?: string; recipientNote?: string
      orderNumber?: string; deliveryCode?: string; recipientWallet?: string
    }
    notes?: string
  }
}

const withKey = () => ({ idempotencyKey: createIdempotencyKey() })

export const deliveriesApi = {
  indexerStatus: () => api.get<IndexerStatus>('/indexer/status'),
  list: (params: { limit?: number; after?: string } = {}) => {
    const query = new URLSearchParams()
    if (params.limit) query.set('limit', String(params.limit))
    if (params.after) query.set('after', params.after)
    const suffix = query.size ? `?${query}` : ''
    return api.get<Projection<ChainDelivery[]>>(`/deliveries${suffix}`)
  },
  get: (id: string) => api.get<Projection<ChainDelivery | null>>(`/deliveries/${id}`),
  bids: (id: string) => api.get<Projection<ChainBid[]>>(`/deliveries/${id}/bids?limit=100`),
  createQuote: (input: CreateQuoteInput) => api.post<QuoteResponse>('/quotes/delivery', input, withKey()),
  quoteStatus: (digest: string) => api.get<QuoteStatus>(`/quotes/${digest}`),
  pickupAcceptance: (id: string) => api.post<AcceptanceResponse>(`/deliveries/${id}/pickup-acceptances`, {}, withKey()),
  returnAcceptance: (id: string) => api.post<AcceptanceResponse>(`/deliveries/${id}/return-acceptances`, {}, withKey()),
  podAttestation: (id: string, code: string) =>
    api.post<PodResponse>(`/deliveries/${id}/pod-attestations`, { proofType: 'otp', code }, withKey()),
}
