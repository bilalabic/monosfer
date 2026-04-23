import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { deliveriesApi } from '@/api/deliveries'

export type DeliveryStatus = 'open' | 'in_progress' | 'completed' | 'disputed'

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
  distance: string
  weight: string
  description: string
  maxBudget: number
  escrowAmount: number
  status: DeliveryStatus
  bids: Bid[]
  selectedBidId?: string
  createdAt: string
  deadline: string
  rating?: number
  timeline: TimelineStep[]
}

const MOCK: Delivery[] = [
  {
    id: 'd1',
    title: 'Elektronik Ürün Teslimatı',
    pickupAddress: 'Kadıköy, İstanbul',
    dropoffAddress: 'Beşiktaş, İstanbul',
    distance: '8.2 km',
    weight: '2.5 kg',
    description: 'Kırılgan elektronik ürün, dikkatli taşıma gerektirir. Orijinal ambalajda.',
    maxBudget: 25,
    escrowAmount: 25,
    status: 'open',
    bids: [
      { id: 'b1', courierId: 'c1', courierName: 'Ahmet Yılmaz', courierAvatar: 'AY', courierRating: 4.9, courierDeliveries: 312, tokenAmount: 18, estimatedTime: '45 dk', createdAt: '2026-04-23T08:30:00Z' },
      { id: 'b2', courierId: 'c3', courierName: 'Fatma Kaya', courierAvatar: 'FK', courierRating: 4.7, courierDeliveries: 198, tokenAmount: 14, estimatedTime: '55 dk', createdAt: '2026-04-23T08:45:00Z' },
    ],
    createdAt: '2026-04-23T08:00:00Z',
    deadline: '2026-04-23T14:00:00Z',
    timeline: [
      { step: 'created', label: 'Talep Oluşturuldu', completed: true, time: '08:00' },
      { step: 'accepted', label: 'Kurye Seçildi', completed: false },
      { step: 'pickup', label: 'Ürün Alındı', completed: false },
      { step: 'transit', label: 'Yolda', completed: false },
      { step: 'delivered', label: 'Teslim Edildi', completed: false },
    ],
  },
  {
    id: 'd2',
    title: 'Belge & Dosya Teslimatı',
    pickupAddress: 'Şişli, İstanbul',
    dropoffAddress: 'Ataşehir, İstanbul',
    distance: '14.5 km',
    weight: '0.3 kg',
    description: 'Hukuki belgeler, imzalı ve mühürlü.',
    maxBudget: 20,
    escrowAmount: 20,
    status: 'open',
    bids: [
      { id: 'b3', courierId: 'c2', courierName: 'Mehmet Demir', courierAvatar: 'MD', courierRating: 4.8, courierDeliveries: 267, tokenAmount: 16, estimatedTime: '50 dk', createdAt: '2026-04-23T09:10:00Z' },
    ],
    createdAt: '2026-04-23T09:00:00Z',
    deadline: '2026-04-23T16:00:00Z',
    timeline: [
      { step: 'created', label: 'Talep Oluşturuldu', completed: true, time: '09:00' },
      { step: 'accepted', label: 'Kurye Seçildi', completed: false },
      { step: 'pickup', label: 'Ürün Alındı', completed: false },
      { step: 'transit', label: 'Yolda', completed: false },
      { step: 'delivered', label: 'Teslim Edildi', completed: false },
    ],
  },
  {
    id: 'd3',
    title: 'Gıda & Market Ürünleri',
    pickupAddress: 'Bakırköy, İstanbul',
    dropoffAddress: 'Zeytinburnu, İstanbul',
    distance: '5.8 km',
    weight: '4.2 kg',
    description: 'Soğuk zinciri gerektiren gıda ürünleri.',
    maxBudget: 15,
    escrowAmount: 15,
    status: 'in_progress',
    selectedBidId: 'b4',
    bids: [
      { id: 'b4', courierId: 'c4', courierName: 'Zeynep Arslan', courierAvatar: 'ZA', courierRating: 4.6, courierDeliveries: 145, tokenAmount: 12, estimatedTime: '30 dk', createdAt: '2026-04-23T09:30:00Z' },
    ],
    createdAt: '2026-04-23T09:15:00Z',
    deadline: '2026-04-23T11:00:00Z',
    timeline: [
      { step: 'created', label: 'Talep Oluşturuldu', completed: true, time: '09:15', role: 'sender' },
      { step: 'escrow', label: "Ödeme Escrow'a Kilitlendi", completed: true, time: '09:16', role: 'system' },
      { step: 'accepted', label: 'Kurye Seçildi (Zeynep Arslan)', completed: true, time: '09:32', role: 'system' },
      { step: 'pickup', label: 'Paket Teslim Alındı', completed: true, time: '09:50', role: 'courier' },
      { step: 'transit', label: 'Yolda', completed: false, role: 'courier' },
      { step: 'delivered', label: 'Teslim Edildi', completed: false, role: 'recipient' },
    ],
  },
  {
    id: 'd4',
    title: 'Kıyafet & Aksesuar Paketi',
    pickupAddress: 'Nişantaşı, İstanbul',
    dropoffAddress: 'Üsküdar, İstanbul',
    distance: '11.3 km',
    weight: '1.8 kg',
    description: 'Online mağaza siparişi.',
    maxBudget: 18,
    escrowAmount: 18,
    status: 'completed',
    selectedBidId: 'b5',
    bids: [
      { id: 'b5', courierId: 'c1', courierName: 'Ahmet Yılmaz', courierAvatar: 'AY', courierRating: 4.9, courierDeliveries: 312, tokenAmount: 15, estimatedTime: '40 dk', createdAt: '2026-04-22T14:00:00Z' },
    ],
    createdAt: '2026-04-22T13:45:00Z',
    deadline: '2026-04-22T18:00:00Z',
    rating: 4.9,
    timeline: [
      { step: 'created', label: 'Talep Oluşturuldu', completed: true, time: '13:45', role: 'sender' },
      { step: 'escrow', label: "Ödeme Escrow'a Kilitlendi", completed: true, time: '13:46', role: 'system' },
      { step: 'accepted', label: 'Kurye Seçildi (Ahmet Yılmaz)', completed: true, time: '14:02', role: 'system' },
      { step: 'pickup', label: 'Paket Teslim Alındı', completed: true, time: '14:25', role: 'courier' },
      { step: 'transit', label: 'Yolda', completed: true, time: '14:28', role: 'courier' },
      { step: 'delivered', label: 'Teslim Edildi', completed: true, time: '15:05', role: 'recipient' },
    ],
  },
  {
    id: 'd5',
    title: 'Tıbbi Malzeme Teslimatı',
    pickupAddress: 'Kartal, İstanbul',
    dropoffAddress: 'Pendik, İstanbul',
    distance: '6.1 km',
    weight: '0.8 kg',
    description: 'İlaç ve tıbbi malzeme.',
    maxBudget: 22,
    escrowAmount: 22,
    status: 'open',
    bids: [],
    createdAt: '2026-04-23T10:00:00Z',
    deadline: '2026-04-23T13:00:00Z',
    timeline: [
      { step: 'created', label: 'Talep Oluşturuldu', completed: true, time: '10:00' },
      { step: 'accepted', label: 'Kurye Seçildi', completed: false },
      { step: 'pickup', label: 'Ürün Alındı', completed: false },
      { step: 'transit', label: 'Yolda', completed: false },
      { step: 'delivered', label: 'Teslim Edildi', completed: false },
    ],
  },
]

export const useDeliveryStore = defineStore('delivery', () => {
  const deliveries = ref<Delivery[]>([...MOCK])
  const loading = ref(false)
  const usingApi = ref(false)

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
    try {
      const data = await deliveriesApi.list()
      if (data.length > 0) {
        deliveries.value = data
        usingApi.value = true
      }
    } catch {
      // Keep mock data, API unavailable
    } finally {
      loading.value = false
    }
  }

  async function createDelivery(formData: {
    title: string; pickupAddress: string; dropoffAddress: string
    weight?: string; description?: string; maxBudget: number; date: string; deadline: string
  }) {
    if (usingApi.value) {
      const newDelivery = await deliveriesApi.create(formData)
      deliveries.value.unshift(newDelivery)
      return newDelivery
    }
    // Mock fallback
    const newDelivery: Delivery = {
      id: `d${Date.now()}`,
      title: formData.title,
      pickupAddress: formData.pickupAddress,
      dropoffAddress: formData.dropoffAddress,
      description: formData.description ?? '',
      maxBudget: formData.maxBudget,
      distance: '—',
      weight: formData.weight ? `${formData.weight} kg` : '—',
      escrowAmount: formData.maxBudget,
      status: 'open',
      bids: [],
      createdAt: new Date().toISOString(),
      deadline: new Date(`${formData.date}T${formData.deadline}`).toISOString(),
      timeline: [
        { step: 'created', label: 'Talep Oluşturuldu', completed: true, time: new Date().toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' }) },
        { step: 'accepted', label: 'Kurye Seçildi', completed: false },
        { step: 'pickup', label: 'Ürün Alındı', completed: false },
        { step: 'transit', label: 'Yolda', completed: false },
        { step: 'delivered', label: 'Teslim Edildi', completed: false },
      ],
    }
    deliveries.value.unshift(newDelivery)
    return newDelivery
  }

  async function addBid(deliveryId: string, bid: Omit<Bid, 'id' | 'createdAt'>) {
    const delivery = deliveries.value.find(d => d.id === deliveryId)
    if (!delivery) return
    if (usingApi.value) {
      try {
        const newBid = await deliveriesApi.addBid(deliveryId, { tokenAmount: bid.tokenAmount, estimatedMinutes: parseInt(bid.estimatedTime) || 45 })
        delivery.bids.push(newBid)
        return
      } catch { /* fall through to mock */ }
    }
    delivery.bids.push({ ...bid, id: `b${Date.now()}`, createdAt: new Date().toISOString() })
  }

  async function selectBid(deliveryId: string, bidId: string) {
    const delivery = deliveries.value.find(d => d.id === deliveryId)
    if (!delivery) return
    if (usingApi.value) {
      try {
        const updated = await deliveriesApi.selectBid(deliveryId, bidId)
        const idx = deliveries.value.findIndex(d => d.id === deliveryId)
        if (idx !== -1) deliveries.value[idx] = updated
        return
      } catch { /* fall through */ }
    }
    delivery.selectedBidId = bidId
    delivery.status = 'in_progress'
    const acceptedStep = delivery.timeline.find(s => s.step === 'accepted')
    if (acceptedStep) {
      acceptedStep.completed = true
      acceptedStep.time = new Date().toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' })
    }
  }

  async function lockEscrow(deliveryId: string) {
    const d = deliveries.value.find(d => d.id === deliveryId)
    if (!d) return
    if (usingApi.value) {
      try {
        const updated = await deliveriesApi.lockEscrow(deliveryId)
        const idx = deliveries.value.findIndex(x => x.id === deliveryId)
        if (idx !== -1) deliveries.value[idx] = updated
        return
      } catch { /* fall through */ }
    }
    const now = new Date().toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' })
    const escrowStep = d.timeline.find(s => s.step === 'escrow')
    if (escrowStep) { escrowStep.completed = true; escrowStep.time = now }
  }

  async function confirmPickup(deliveryId: string) {
    const d = deliveries.value.find(d => d.id === deliveryId)
    if (!d) return
    if (usingApi.value) {
      try {
        const updated = await deliveriesApi.confirmPickup(deliveryId)
        const idx = deliveries.value.findIndex(x => x.id === deliveryId)
        if (idx !== -1) deliveries.value[idx] = updated
        return
      } catch { /* fall through */ }
    }
    const now = new Date().toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' })
    for (const s of d.timeline) {
      if ((s.step === 'pickup' || s.step === 'transit') && !s.completed) {
        s.completed = true; s.time = now
      }
    }
  }

  async function completeDelivery(deliveryId: string) {
    const d = deliveries.value.find(d => d.id === deliveryId)
    if (!d) return
    if (usingApi.value) {
      try {
        const updated = await deliveriesApi.completeDelivery(deliveryId)
        const idx = deliveries.value.findIndex(x => x.id === deliveryId)
        if (idx !== -1) deliveries.value[idx] = updated
        return
      } catch { /* fall through */ }
    }
    d.status = 'completed'
    const now = new Date().toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' })
    for (const s of d.timeline) {
      if (!s.completed) { s.completed = true; s.time = now }
    }
  }

  return {
    deliveries, loading, usingApi, filteredDeliveries, selectedFilter,
    getDelivery, loadDeliveries, createDelivery,
    addBid, selectBid, lockEscrow, confirmPickup, completeDelivery,
  }
})
