import { api } from './client'
import { MONAD_TESTNET } from '@/config/chain'

export interface DevelopmentDelivery {
  id: string
  title: string
  pickupArea: string
  dropoffArea: string
  distance: string
  weight: string
  description: string
  budget: number
  createdAt: string
}
export interface DevelopmentCourier {
  walletAddress: string
  name: string
  vehicleType: string
  joinedDate: string
}
export function developmentDataset(): Promise<{ deliveries: DevelopmentDelivery[]; couriers: DevelopmentCourier[] }> {
  if (MONAD_TESTNET.chainId !== 31337) return Promise.resolve({ deliveries: [], couriers: [] })
  return api.get('/development/dataset')
}
