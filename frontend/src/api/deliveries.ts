import { api } from './client'
import type { Delivery, Bid } from '@/stores/useDeliveryStore'

export const deliveriesApi = {
  list: (params?: { status?: string; search?: string }) => {
    const qs = params ? '?' + new URLSearchParams(params as Record<string, string>).toString() : ''
    return api.get<Delivery[]>(`/deliveries${qs}`)
  },

  get: (id: string) => api.get<Delivery>(`/deliveries/${id}`),

  create: (data: {
    title: string
    pickupAddress: string
    dropoffAddress: string
    recipientName?: string
    recipientPhone?: string
    recipientWallet?: string
    deliveryCode?: string
    weight?: string
    description?: string
    maxBudget: number
    date: string
    deadline: string
    packageType?: string
    urgency?: string
  }) => api.post<Delivery>('/deliveries', data),

  addBid: (deliveryId: string, data: { tokenAmount: number; estimatedMinutes?: number }) =>
    api.post<Bid>(`/deliveries/${deliveryId}/bids`, data),

  selectBid: (deliveryId: string, bidId: string) =>
    api.patch<Delivery>(`/deliveries/${deliveryId}/select-bid`, { bidId }),

  lockEscrow: (deliveryId: string, txHash?: string) =>
    api.patch<Delivery>(`/deliveries/${deliveryId}/escrow`, txHash ? { txHash } : {}),

  confirmPickup: (deliveryId: string, txHash?: string) =>
    api.patch<Delivery>(`/deliveries/${deliveryId}/pickup`, txHash ? { txHash } : {}),

  completeDelivery: (deliveryId: string, txHash?: string) =>
    api.patch<Delivery>(`/deliveries/${deliveryId}/complete`, txHash ? { txHash } : {}),

  completeDeliveryWithRecipientCode: (deliveryId: string, deliveryCode: string, txHash?: string) =>
    api.patch<Delivery>(`/deliveries/${deliveryId}/recipient-complete`, txHash ? { deliveryCode, txHash } : { deliveryCode }),

  rateDelivery: (deliveryId: string, data: { rating: number; comment?: string }) =>
    api.patch<Delivery>(`/deliveries/${deliveryId}/rating`, data),
}
