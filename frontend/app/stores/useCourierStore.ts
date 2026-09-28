import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { couriersApi } from '@/api/couriers'

export interface Courier {
  id: string
  walletAddress?: string
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
  badge?: 'gold' | 'silver' | 'bronze'
  specialties: string[]
}

export const useCourierStore = defineStore('courier', () => {
  const couriers = ref<Courier[]>([])
  const loading = ref(false)
  const error = ref('')

  async function loadCouriers() {
    loading.value = true
    error.value = ''
    try {
      couriers.value = await couriersApi.list()
    } catch (e) {
      error.value = e instanceof Error ? e.message : 'Kuryeler yüklenemedi'
    } finally {
      loading.value = false
    }
  }

  const leaderboard = computed(() => {
    return [...couriers.value].sort((a, b) => a.name.localeCompare(b.name))
  })

  // V2 public projections expose bid participation, not a canonical reputation ranking.
  const topThree = computed<Courier[]>(() => [])

  function getCourier(id: string) {
    return couriers.value.find(c => c.id === id)
  }

  return { couriers, loading, error, leaderboard, topThree, getCourier, loadCouriers }
})
