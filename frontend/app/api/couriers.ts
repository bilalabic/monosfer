import { deliveriesApi } from './deliveries'
import { developmentDataset } from './development'

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
  async list(): Promise<CourierApiData[]> {
    const nuxtApp = useNuxtApp()
    const [deliveries, dataset] = await Promise.all([deliveriesApi.list({ limit: 100 }), developmentDataset()])
    const pages = await nuxtApp.runWithContext(() => Promise.all(deliveries.data.map(delivery => deliveriesApi.bids(delivery.id))))
    const wallets = new Set(pages.flatMap(page => page.data.map(bid => bid.courier.toLowerCase())))
    return [...wallets].map((walletAddress, index) => ({
      id: walletAddress,
      walletAddress,
      name: dataset.couriers.find(courier => courier.walletAddress === walletAddress)?.name || `${walletAddress.slice(0, 6)}...${walletAddress.slice(-4)}`,
      avatar: '',
      rating: 0,
      totalDeliveries: 0,
      successRate: 0,
      onTimeRate: 0,
      weeklyDeliveries: 0,
      weeklyEarnings: 0,
      monthlyEarnings: 0,
      joinedDate: dataset.couriers.find(courier => courier.walletAddress === walletAddress)?.joinedDate || '',
      specialties: [dataset.couriers.find(courier => courier.walletAddress === walletAddress)?.vehicleType || ''].filter(Boolean),
      leaderboardScore: index,
    }))
  },
  async locations(): Promise<CourierLocation[]> {
    // V2 deliberately exposes live locations only through scoped tracking sessions.
    return []
  },
}
