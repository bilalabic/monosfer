import { defineStore } from 'pinia'
import { ref, computed } from 'vue'

export interface Courier {
  id: string
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
  const couriers = ref<Courier[]>([
    {
      id: 'c1',
      name: 'Ahmet Yılmaz',
      avatar: 'AY',
      rating: 4.9,
      totalDeliveries: 312,
      successRate: 99.4,
      onTimeRate: 97.8,
      weeklyDeliveries: 28,
      weeklyEarnings: 420,
      monthlyEarnings: 1680,
      joinedDate: '2025-08-12',
      badge: 'gold',
      specialties: ['Elektronik', 'Kırılgan'],
    },
    {
      id: 'c2',
      name: 'Mehmet Demir',
      avatar: 'MD',
      rating: 4.8,
      totalDeliveries: 267,
      successRate: 98.9,
      onTimeRate: 96.2,
      weeklyDeliveries: 24,
      weeklyEarnings: 368,
      monthlyEarnings: 1472,
      joinedDate: '2025-09-03',
      badge: 'silver',
      specialties: ['Belge', 'Hızlı Teslimat'],
    },
    {
      id: 'c3',
      name: 'Fatma Kaya',
      avatar: 'FK',
      rating: 4.7,
      totalDeliveries: 198,
      successRate: 98.0,
      onTimeRate: 94.9,
      weeklyDeliveries: 19,
      weeklyEarnings: 285,
      monthlyEarnings: 1140,
      joinedDate: '2025-10-15',
      badge: 'bronze',
      specialties: ['Gıda', 'Soğuk Zincir'],
    },
    {
      id: 'c4',
      name: 'Zeynep Arslan',
      avatar: 'ZA',
      rating: 4.6,
      totalDeliveries: 145,
      successRate: 97.2,
      onTimeRate: 93.1,
      weeklyDeliveries: 15,
      weeklyEarnings: 215,
      monthlyEarnings: 860,
      joinedDate: '2025-11-20',
      specialties: ['Market', 'Gıda'],
    },
    {
      id: 'c5',
      name: 'Burak Şahin',
      avatar: 'BŞ',
      rating: 4.5,
      totalDeliveries: 112,
      successRate: 96.4,
      onTimeRate: 91.8,
      weeklyDeliveries: 12,
      weeklyEarnings: 178,
      monthlyEarnings: 712,
      joinedDate: '2025-12-05',
      specialties: ['Kıyafet', 'Aksesuar'],
    },
    {
      id: 'c6',
      name: 'Elif Çelik',
      avatar: 'EÇ',
      rating: 4.4,
      totalDeliveries: 89,
      successRate: 95.5,
      onTimeRate: 90.1,
      weeklyDeliveries: 10,
      weeklyEarnings: 148,
      monthlyEarnings: 592,
      joinedDate: '2026-01-10',
      specialties: ['Tıbbi', 'Hassas'],
    },
    {
      id: 'c7',
      name: 'Hasan Polat',
      avatar: 'HP',
      rating: 4.3,
      totalDeliveries: 67,
      successRate: 94.0,
      onTimeRate: 88.5,
      weeklyDeliveries: 8,
      weeklyEarnings: 112,
      monthlyEarnings: 448,
      joinedDate: '2026-02-01',
      specialties: ['Genel'],
    },
    {
      id: 'c8',
      name: 'Ayşe Güneş',
      avatar: 'AG',
      rating: 4.2,
      totalDeliveries: 45,
      successRate: 93.3,
      onTimeRate: 86.7,
      weeklyDeliveries: 6,
      weeklyEarnings: 84,
      monthlyEarnings: 336,
      joinedDate: '2026-02-20',
      specialties: ['Genel'],
    },
  ])

  const leaderboard = computed(() =>
    [...couriers.value].sort((a, b) => {
      const scoreA = a.rating * 20 + a.totalDeliveries * 0.1 + a.onTimeRate * 0.5
      const scoreB = b.rating * 20 + b.totalDeliveries * 0.1 + b.onTimeRate * 0.5
      return scoreB - scoreA
    }),
  )

  const topThree = computed(() => leaderboard.value.slice(0, 3))

  function getCourier(id: string) {
    return couriers.value.find(c => c.id === id)
  }

  return { couriers, leaderboard, topThree, getCourier }
})
