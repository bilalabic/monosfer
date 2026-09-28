import { api, createIdempotencyKey } from './client'

export type SupportCaseStatus = 'open' | 'investigating' | 'closed'

export interface SupportCase {
  id: string
  stream: string
  delivery_id: string
  status: SupportCaseStatus
  assignee: string | null
  created_by: string
  created_at: string
  updated_at: string
}

export interface SupportCaseList {
  data: SupportCase[]
  nextCursor?: string | null
}

export interface SupportCaseDetail extends SupportCase {
  events: unknown[]
}

export interface CreateSupportCaseInput {
  id: string
  assignee?: string
  note?: string
}

export interface UpdateSupportCaseInput {
  status?: SupportCaseStatus
  assignee?: string | null
  note?: string
}

export interface SupportEvidenceMeta {
  id: string
  content_type: string
  status: string
  created_at: string
}

export interface SupportEvidenceList {
  data: SupportEvidenceMeta[]
  hasMore: boolean
}

export interface ReputationCounters {
  customerDeliveries: string
  courierDeliveries: string
  customerCompleted: string
  courierCompleted: string
  returned: string
  cancelled: string
  expired: string
  referral: 'pending_policy' | string
  reward: 'pending_policy' | string
}

export const supportApi = {
  listCases: (params: { limit?: number; after?: string } = {}) => {
    const query = new URLSearchParams()
    if (params.limit) query.set('limit', String(params.limit))
    if (params.after) query.set('after', params.after)
    const suffix = query.size ? `?${query}` : ''
    return api.get<SupportCaseList>(`/support/cases${suffix}`)
  },
  createCase: (input: CreateSupportCaseInput) =>
    api.post<SupportCase>('/support/cases', input, { idempotencyKey: createIdempotencyKey() }),
  getCase: (caseId: string) => api.get<SupportCaseDetail>(`/support/cases/${caseId}`),
  updateCase: (caseId: string, input: UpdateSupportCaseInput) =>
    api.patch<SupportCase>(`/support/cases/${caseId}`, input),
  getDelivery: (deliveryId: string) => api.get<Record<string, unknown>>(`/support/deliveries/${deliveryId}`),
  getDeliveryPrivate: (deliveryId: string) =>
    api.get<Record<string, unknown>>(`/support/deliveries/${deliveryId}/private`),
  getDeliveryEvidence: (deliveryId: string) =>
    api.get<SupportEvidenceList>(`/support/deliveries/${deliveryId}/evidence`),
  getDeliveryEvidenceContent: (deliveryId: string, evidenceId: string) =>
    api.get<Record<string, unknown>>(`/support/deliveries/${deliveryId}/evidence/${evidenceId}/content`),
  myReputation: () => api.get<ReputationCounters>('/users/me/reputation'),
  walletReputation: (wallet: string) => api.get<ReputationCounters>(`/support/wallets/${wallet}/reputation`),
}
