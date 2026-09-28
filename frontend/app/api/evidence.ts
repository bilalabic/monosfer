import { api, createIdempotencyKey } from './client'

export const EVIDENCE_TEXT_MAX_BYTES = 8192
export const EVIDENCE_IMAGE_MAX_BYTES = 24576

export interface EvidenceGps {
  lat: number
  lng: number
  capturedAt: string
}

export type EvidenceUploadInput =
  | { contentType: 'text/plain'; text: string; gps?: EvidenceGps }
  | { contentType: 'image/png' | 'image/jpeg'; contentBase64: string; gps?: EvidenceGps }

export interface EvidenceUploadResponse {
  evidenceId: string
  status: string
  contentType: string
}

export interface EvidenceMeta {
  evidenceId: string
  status: string
  contentType: string
  createdAt: string
}

export interface EvidenceContent {
  evidenceHash: string
  contentType: string
  text?: string
  contentBase64?: string
  gps?: EvidenceGps
}

export const evidenceApi = {
  upload: (deliveryId: string, input: EvidenceUploadInput) =>
    api.post<EvidenceUploadResponse>(`/deliveries/${deliveryId}/evidence`, input, {
      idempotencyKey: createIdempotencyKey(),
    }),
  list: (deliveryId: string) => api.get<EvidenceMeta[]>(`/deliveries/${deliveryId}/evidence`),
  content: (deliveryId: string, evidenceId: string) =>
    api.get<EvidenceContent>(`/deliveries/${deliveryId}/evidence/${evidenceId}/content`),
}
