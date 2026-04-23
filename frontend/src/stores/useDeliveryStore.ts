import { defineStore } from 'pinia'
import { ref, computed } from 'vue'

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

export const useDeliveryStore = defineStore('delivery', () => {
  const deliveries = ref<Delivery[]>([
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
        {
          id: 'b1',
          courierId: 'c1',
          courierName: 'Ahmet Yılmaz',
          courierAvatar: 'AY',
          courierRating: 4.9,
          courierDeliveries: 312,
          tokenAmount: 18,
          estimatedTime: '45 dk',
          createdAt: '2026-04-23T08:30:00Z',
        },
        {
          id: 'b2',
          courierId: 'c3',
          courierName: 'Fatma Kaya',
          courierAvatar: 'FK',
          courierRating: 4.7,
          courierDeliveries: 198,
          tokenAmount: 14,
          estimatedTime: '55 dk',
          createdAt: '2026-04-23T08:45:00Z',
        },
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
      description: 'Hukuki belgeler, imzalı ve mühürlü. Teslimatta alıcı imzası gerekiyor.',
      maxBudget: 20,
      escrowAmount: 20,
      status: 'open',
      bids: [
        {
          id: 'b3',
          courierId: 'c2',
          courierName: 'Mehmet Demir',
          courierAvatar: 'MD',
          courierRating: 4.8,
          courierDeliveries: 267,
          tokenAmount: 16,
          estimatedTime: '50 dk',
          createdAt: '2026-04-23T09:10:00Z',
        },
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
      description: 'Soğuk zinciri gerektiren gıda ürünleri. Hızlı teslimat öncelikli.',
      maxBudget: 15,
      escrowAmount: 15,
      status: 'in_progress',
      selectedBidId: 'b4',
      bids: [
        {
          id: 'b4',
          courierId: 'c4',
          courierName: 'Zeynep Arslan',
          courierAvatar: 'ZA',
          courierRating: 4.6,
          courierDeliveries: 145,
          tokenAmount: 12,
          estimatedTime: '30 dk',
          createdAt: '2026-04-23T09:30:00Z',
        },
      ],
      createdAt: '2026-04-23T09:15:00Z',
      deadline: '2026-04-23T11:00:00Z',
      timeline: [
        { step: 'created', label: 'Talep Oluşturuldu', completed: true, time: '09:15', role: 'sender' },
        { step: 'escrow', label: 'Ödeme Escrow\'a Kilitlendi', completed: true, time: '09:16', role: 'system' },
        { step: 'accepted', label: 'Kurye Seçildi (Zeynep Arslan)', completed: true, time: '09:32', role: 'system' },
        { step: 'pickup', label: 'Paket Teslim Alındı', completed: true, time: '09:50', role: 'courier' },
        { step: 'transit', label: 'Yolda', completed: false, role: 'courier' },
        { step: 'notification', label: 'Alıcıya Bildirim Gönderildi', completed: false, role: 'recipient' },
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
      description: 'Online mağaza siparişi. Naylon poşete sarılı, hasar vermemek önemli.',
      maxBudget: 18,
      escrowAmount: 18,
      status: 'completed',
      selectedBidId: 'b5',
      bids: [
        {
          id: 'b5',
          courierId: 'c1',
          courierName: 'Ahmet Yılmaz',
          courierAvatar: 'AY',
          courierRating: 4.9,
          courierDeliveries: 312,
          tokenAmount: 15,
          estimatedTime: '40 dk',
          createdAt: '2026-04-22T14:00:00Z',
        },
      ],
      createdAt: '2026-04-22T13:45:00Z',
      deadline: '2026-04-22T18:00:00Z',
      rating: 4.9,
      timeline: [
        { step: 'created', label: 'Talep Oluşturuldu', completed: true, time: '13:45', role: 'sender' },
        { step: 'escrow', label: 'Ödeme Escrow\'a Kilitlendi', completed: true, time: '13:46', role: 'system' },
        { step: 'accepted', label: 'Kurye Seçildi (Ahmet Yılmaz)', completed: true, time: '14:02', role: 'system' },
        { step: 'pickup', label: 'Paket Teslim Alındı', completed: true, time: '14:25', role: 'courier' },
        { step: 'transit', label: 'Yolda', completed: true, time: '14:28', role: 'courier' },
        { step: 'notification', label: 'Alıcıya Bildirim Gönderildi', completed: true, time: '14:55', role: 'recipient' },
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
      description: 'İlaç ve tıbbi malzeme. Kırılgan ve hassas ürün, dikey taşıma.',
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
  ])

  const selectedFilter = ref<'all' | DeliveryStatus>('all')

  const filteredDeliveries = computed(() => {
    if (selectedFilter.value === 'all') return deliveries.value
    return deliveries.value.filter(d => d.status === selectedFilter.value)
  })

  function getDelivery(id: string) {
    return deliveries.value.find(d => d.id === id)
  }

  function addBid(deliveryId: string, bid: Omit<Bid, 'id' | 'createdAt'>) {
    const delivery = deliveries.value.find(d => d.id === deliveryId)
    if (!delivery) return
    delivery.bids.push({
      ...bid,
      id: `b${Date.now()}`,
      createdAt: new Date().toISOString(),
    })
  }

  function selectBid(deliveryId: string, bidId: string) {
    const delivery = deliveries.value.find(d => d.id === deliveryId)
    if (!delivery) return
    delivery.selectedBidId = bidId
    delivery.status = 'in_progress'
    const acceptedStep = delivery.timeline.find(s => s.step === 'accepted')
    if (acceptedStep) {
      acceptedStep.completed = true
      acceptedStep.time = new Date().toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' })
    }
  }

  return { deliveries, filteredDeliveries, selectedFilter, getDelivery, addBid, selectBid }
})
