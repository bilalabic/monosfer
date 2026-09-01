import { api } from './client'

export interface CourierApiData {
  id: string
  walletAddress: string
  name: string
  avatar: string
  rating: number
  totalDeliveries: number
  successRate: number
  onTimeRate: number
  weeklyDeliveries: number
  weeklyEarnings: number
  monthlyEarnings: number
  joinedDate: string
  specialties: string[]
  leaderboardScore: number
}

export interface CourierLocation {
  id: string
  walletAddress: string
  name: string
  avatar: string
  isOnline: boolean
  vehicleType: 'bicycle' | 'motorcycle' | 'car' | 'on_foot'
  lat: number
  lng: number
  locationUpdatedAt: string | null
}

export const couriersApi = {
  list: () => api.get<CourierApiData[]>('/couriers'),
  locations: () => api.get<CourierLocation[]>('/couriers/locations'),
}
