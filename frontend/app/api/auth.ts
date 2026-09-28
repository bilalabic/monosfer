import { api } from './client'

export type UserRole = 'customer' | 'courier'
export type VehicleType = 'on_foot' | 'bicycle' | 'motorcycle' | 'car'

export interface AuthUser {
  id: string
  walletAddress: string
  role: UserRole
  displayName: string | null
  email: string | null
  phone: string | null
  courierProfile: { vehicleType: VehicleType } | null
  createdAt: string
  updatedAt: string
}

export interface SessionResponse {
  user: AuthUser
  session: { expiresAt: string }
  csrfToken: string
}

export interface NonceResponse {
  address: string
  nonce: string
  message: string
  expiresAt: string
}

export interface UpdateProfileInput {
  displayName?: string | null
  email?: string | null
  phone?: string | null
  role?: UserRole
  courierProfile?: { vehicleType: VehicleType } | null
}

export const authApi = {
  nonce: (address: string) => api.post<NonceResponse>('/auth/siwe/nonce', { address }),
  verify: (message: string, signature: string) =>
    api.post<SessionResponse>('/auth/siwe/verify', { message, signature }),
  session: () => api.get<SessionResponse>('/auth/session'),
  me: () => api.get<AuthUser>('/users/me'),
  updateMe: (data: UpdateProfileInput) => api.patch<AuthUser>('/users/me', data),
  logout: () => api.delete('/auth/session'),
  logoutAll: () => api.delete('/auth/sessions'),
}
