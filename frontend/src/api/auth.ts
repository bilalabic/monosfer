import { api } from './client'

export type UserRole = 'customer' | 'courier' | 'both'

export interface AuthUser {
  id: string
  walletAddress: string
  name: string
  email: string
  phone: string
  role: UserRole
  rating: number
  balance: number
}

export interface AuthResponse {
  user: AuthUser
  token: string
}

export interface AuthProfileResponse {
  user: AuthUser
}

export const authApi = {
  register: (data: { walletAddress: string; name: string; email: string; phone: string; role: UserRole }) =>
    api.post<AuthResponse>('/auth/register', data),

  login: (data: { walletAddress: string; email?: string; name?: string; phone?: string; role?: UserRole }) =>
    api.post<AuthResponse>('/auth/login', data),

  me: () => api.get<AuthProfileResponse>('/auth/me'),

  updateMe: (data: { name?: string; email?: string; phone?: string; role?: UserRole }) =>
    api.patch<AuthProfileResponse>('/auth/me', data),
}
