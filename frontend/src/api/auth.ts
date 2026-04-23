import { api } from './client'

export interface AuthUser {
  id: string
  walletAddress: string
  name: string
  email: string
  phone: string
  role: 'customer' | 'courier'
  rating: number
  balance: number
}

export interface AuthResponse {
  user: AuthUser
  token: string
}

export const authApi = {
  register: (data: { walletAddress: string; name: string; email: string; phone: string; role: string }) =>
    api.post<AuthResponse>('/auth/register', data),

  login: (data: { walletAddress: string; email?: string; name?: string; phone?: string; role?: string }) =>
    api.post<AuthResponse>('/auth/login', data),
}
