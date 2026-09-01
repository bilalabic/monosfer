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
    const sorted = [...couriers.value].sort((a, b) => {
      const scoreA = a.rating * 20 + a.totalDeliveries * 0.1 + a.onTimeRate * 0.5
      const scoreB = b.rating * 20 + b.totalDeliveries * 0.1 + b.onTimeRate * 0.5
      return scoreB - scoreA
    })
    return sorted.map((c, i) => ({
      ...c,
      badge: i === 0 ? ('gold' as const) : i === 1 ? ('silver' as const) : i === 2 ? ('bronze' as const) : undefined,
    }))
  })

  const topThree = computed(() => leaderboard.value.slice(0, 3))

  function getCourier(id: string) {
    return couriers.value.find(c => c.id === id)
  }

  return { couriers, loading, error, leaderboard, topThree, getCourier, loadCouriers }
})
