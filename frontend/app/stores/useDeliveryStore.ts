import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { deliveriesApi } from '@/api/deliveries'

export type DeliveryStatus = 'open' | 'in_progress' | 'completed' | 'disputed'
export type RecipientType = 'person' | 'business' | 'office' | 'other'

export interface Bid {
  id: string
  courierId: string
  courierName: string
  courierAvatar: string
  courierRating: number
  courierDeliveries: number
  tokenAmount: number
  estimatedTime: string
  createdAt: string
}

export interface TimelineStep {
  step: string
  label: string
  completed: boolean
  time?: string
  role?: 'sender' | 'courier' | 'recipient' | 'system'
}

export interface Delivery {
  id: string
  title: string
  pickupAddress: string
  dropoffAddress: string
  recipientType?: RecipientType
  recipientName?: string
  businessName?: string
  contactPerson?: string
  orderRef?: string
  department?: string
  recipientPhone?: string
  recipientNote?: string
  requiresRecipientCode?: boolean
  deliveryConfirmedBy?: 'sender_wallet' | 'recipient_code'
  distance: string
  weight: string
  description: string
  maxBudget: number
  escrowAmount: number
  status: DeliveryStatus
  bids: Bid[]
  selectedBidId?: string
  senderId?: string
  assignedCourierId?: string | null
  createdAt: string
  deadline: string
  rating?: number
  ratingComment?: string
  isRated?: boolean
  timeline: TimelineStep[]
}

export const useDeliveryStore = defineStore('delivery', () => {
  const deliveries = ref<Delivery[]>([])
  const loading = ref(false)
  const error = ref('')

  const selectedFilter = ref<'all' | DeliveryStatus>('all')

  const filteredDeliveries = computed(() => {
    if (selectedFilter.value === 'all') return deliveries.value
    return deliveries.value.filter(d => d.status === selectedFilter.value)
  })

  function getDelivery(id: string) {
    return deliveries.value.find(d => d.id === id)
  }

  async function loadDeliveries() {
    loading.value = true
    error.value = ''
    try {
      deliveries.value = await deliveriesApi.list()
    } catch (e) {
      error.value = e instanceof Error ? e.message : 'Teslimatlar yüklenemedi'
    } finally {
      loading.value = false
    }
  }

  async function createDelivery(formData: {
    title: string; pickupAddress: string; dropoffAddress: string
    recipientType?: RecipientType; recipientName?: string; businessName?: string; contactPerson?: string
    orderRef?: string; department?: string; recipientPhone?: string; recipientWallet?: string; recipientNote?: string; deliveryCode?: string
    weight?: string; description?: string; maxBudget: number; date: string; deadline: string
  }) {
    const newDelivery = await deliveriesApi.create(formData)
    deliveries.value.unshift(newDelivery)
    return newDelivery
  }

  async function addBid(deliveryId: string, bid: Omit<Bid, 'id' | 'createdAt'>) {
    const delivery = deliveries.value.find(d => d.id === deliveryId)
    if (!delivery) return
    const newBid = await deliveriesApi.addBid(deliveryId, {
      tokenAmount: bid.tokenAmount,
      estimatedMinutes: parseInt(bid.estimatedTime) || 45,
    })
    delivery.bids.push(newBid)
  }

  async function selectBid(deliveryId: string, bidId: string) {
    const updated = await deliveriesApi.selectBid(deliveryId, bidId)
    const idx = deliveries.value.findIndex(d => d.id === deliveryId)
    if (idx !== -1) deliveries.value[idx] = updated
  }

  async function lockEscrow(deliveryId: string, txHash?: string) {
    const updated = await deliveriesApi.lockEscrow(deliveryId, txHash)
    const idx = deliveries.value.findIndex(d => d.id === deliveryId)
    if (idx !== -1) deliveries.value[idx] = updated
  }

  async function confirmPickup(deliveryId: string, txHash?: string) {
    const updated = await deliveriesApi.confirmPickup(deliveryId, txHash)
    const idx = deliveries.value.findIndex(d => d.id === deliveryId)
    if (idx !== -1) deliveries.value[idx] = updated
  }

  async function completeDelivery(deliveryId: string, txHash?: string) {
    const updated = await deliveriesApi.completeDelivery(deliveryId, txHash)
    const idx = deliveries.value.findIndex(d => d.id === deliveryId)
    if (idx !== -1) deliveries.value[idx] = updated
  }

  async function completeDeliveryWithRecipientCode(deliveryId: string, deliveryCode: string, txHash?: string) {
    const updated = await deliveriesApi.completeDeliveryWithRecipientCode(deliveryId, deliveryCode, txHash)
    const idx = deliveries.value.findIndex(d => d.id === deliveryId)
    if (idx !== -1) deliveries.value[idx] = updated
    return updated
  }

  async function rateDelivery(deliveryId: string, rating: number, comment?: string) {
    const updated = await deliveriesApi.rateDelivery(deliveryId, { rating, comment })
    const idx = deliveries.value.findIndex(d => d.id === deliveryId)
    if (idx !== -1) deliveries.value[idx] = updated
    return updated
  }

  return {
    deliveries, loading, error, filteredDeliveries, selectedFilter,
    getDelivery, loadDeliveries, createDelivery,
    addBid, selectBid, lockEscrow, confirmPickup, completeDelivery, completeDeliveryWithRecipientCode, rateDelivery,
  }
})
