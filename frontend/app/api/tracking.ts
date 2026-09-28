import { api } from './client'

export type TrackingMode = 'publish' | 'view'

export interface TrackingSession {
  trackingSession: string
  expiresAt: string
  mode: TrackingMode
}

export interface TrackingLocationData {
  lat: number
  lng: number
  sequence: number
  capturedAt: string
  accuracyMeters?: number
  receivedAt?: string
  expiresAt?: string
}

export interface TrackingLocationResponse {
  eventId: string | null
  location: TrackingLocationData | null
}

export interface RouteEstimate {
  provider: string
  distanceMeters: number
  durationSeconds: number
  estimatedAt: string
  expiresAt: string
}

export interface PostLocationInput {
  lat: number
  lng: number
  sequence: number
  capturedAt: string
  accuracyMeters?: number
}

const sessionHeader = (token: string) => ({ headers: { 'x-tracking-session': token } })

export const trackingApi = {
  startSession: (deliveryId: string) =>
    api.post<TrackingSession>(`/deliveries/${deliveryId}/tracking/sessions`, {}),
  endSession: (deliveryId: string, token: string) =>
    api.delete<void>(`/deliveries/${deliveryId}/tracking/sessions`, sessionHeader(token)),
  postLocation: (deliveryId: string, token: string, input: PostLocationInput) =>
    api.post<{ eventId: string }>(`/deliveries/${deliveryId}/tracking/location`, input, sessionHeader(token)),
  getLocation: (deliveryId: string, token: string) =>
    api.get<TrackingLocationResponse>(`/deliveries/${deliveryId}/tracking/location`, sessionHeader(token)),
  route: (deliveryId: string) => api.get<RouteEstimate>(`/deliveries/${deliveryId}/route`),
}
