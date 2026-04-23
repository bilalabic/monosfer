<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useCourierStore } from '@/stores/useCourierStore'
import { useDeliveryStore } from '@/stores/useDeliveryStore'
import { useWalletStore } from '@/stores/useWalletStore'
import TopCourierCard from '@/components/TopCourierCard.vue'
import LeaderboardTable from '@/components/LeaderboardTable.vue'
import { PhTrophy, PhMedal, PhChartBar, PhStar, PhPackage } from '@phosphor-icons/vue'

const store = useCourierStore()
const deliveryStore = useDeliveryStore()
const wallet = useWalletStore()
const ratingByDelivery = ref<Record<string, number>>({})
const commentByDelivery = ref<Record<string, string>>({})
const ratingSaving = ref<Record<string, boolean>>({})
const ratingError = ref<Record<string, string>>({})

onMounted(() => {
  store.loadCouriers()
  if (deliveryStore.deliveries.length === 0) deliveryStore.loadDeliveries()
})

const podium = computed(() => {
  const [first, second, third] = store.topThree
  if (!first || !second || !third) return null
  return { first, second, third }
})

const pendingRatings = computed(() => {
  const address = wallet.address.toLowerCase()
  if (!address) return []
  return deliveryStore.deliveries.filter(delivery =>
    delivery.status === 'completed' &&
    delivery.senderId?.toLowerCase() === address &&
    !delivery.isRated &&
    !!delivery.assignedCourierId,
  )
})

function selectedCourierName(deliveryId: string) {
  const delivery = deliveryStore.getDelivery(deliveryId)
  const bid = delivery?.bids.find(item => item.id === delivery.selectedBidId)
  return bid?.courierName || 'Kurye'
}

function selectedRating(deliveryId: string) {
  return ratingByDelivery.value[deliveryId] || 5
}

function setRating(deliveryId: string, rating: number) {
  ratingByDelivery.value = { ...ratingByDelivery.value, [deliveryId]: rating }
}

function setComment(deliveryId: string, event: Event) {
  const target = event.target
  if (!(target instanceof HTMLTextAreaElement)) return
  commentByDelivery.value = { ...commentByDelivery.value, [deliveryId]: target.value }
}

async function submitRating(deliveryId: string) {
  ratingSaving.value = { ...ratingSaving.value, [deliveryId]: true }
  ratingError.value = { ...ratingError.value, [deliveryId]: '' }
  try {
    await deliveryStore.rateDelivery(
      deliveryId,
      selectedRating(deliveryId),
      commentByDelivery.value[deliveryId] || '',
    )
    await store.loadCouriers()
  } catch (error) {
    ratingError.value = {
      ...ratingError.value,
      [deliveryId]: error instanceof Error ? error.message : 'Puan kaydedilemedi',
    }
  } finally {
    ratingSaving.value = { ...ratingSaving.value, [deliveryId]: false }
  }
}
</script>

<template>
  <div class="mx-auto max-w-6xl px-5 py-10 sm:px-8">
    <div class="mb-8">
      <p class="mb-1 text-xs font-semibold uppercase tracking-widest text-orange-500">Haftalık Sıralama</p>
      <h1 class="flex items-center gap-2 text-2xl font-bold text-stone-900 sm:text-3xl">
        <PhTrophy class="size-8 text-orange-500" weight="duotone" />
        Kurye Liderlik Tablosu
      </h1>
      <p class="mt-1 text-stone-500">Her pazar gecesi ödüller akıllı sözleşme tarafından otomatik dağıtılır</p>
    </div>

    <!-- Prize Pool -->
    <div class="mb-8 rounded-xl border border-amber-200 bg-amber-50 p-5">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <p class="text-xs font-semibold text-amber-600">Bu Haftanın Ödül Havuzu</p>
          <p class="mt-1 text-3xl font-extrabold text-stone-900">2,400 MON</p>
        </div>
        <div class="flex gap-6 text-center text-sm">
          <div>
            <p class="text-lg font-bold text-amber-600">1,200</p>
            <p class="flex items-center justify-center gap-1 text-xs text-stone-500">
              <PhMedal class="size-4 text-amber-500" weight="fill" /> 1. Sıra
            </p>
          </div>
          <div>
            <p class="text-lg font-bold text-stone-500">720</p>
            <p class="flex items-center justify-center gap-1 text-xs text-stone-500">
              <PhMedal class="size-4 text-stone-400" weight="fill" /> 2. Sıra
            </p>
          </div>
          <div>
            <p class="text-lg font-bold text-orange-500">480</p>
            <p class="flex items-center justify-center gap-1 text-xs text-stone-500">
              <PhMedal class="size-4 text-orange-700" weight="fill" /> 3. Sıra
            </p>
          </div>
        </div>
      </div>
    </div>

    <div v-if="wallet.connected && pendingRatings.length > 0" class="mb-8 rounded-xl border border-stone-200 bg-white p-5">
      <div class="mb-4 flex items-center gap-2">
        <PhStar class="size-5 text-amber-500" weight="duotone" />
        <h2 class="font-semibold text-stone-900">Puan Bekleyen Kuryeler</h2>
      </div>
      <div class="grid gap-3 md:grid-cols-2">
        <div v-for="delivery in pendingRatings" :key="delivery.id" class="rounded-xl border border-stone-100 bg-stone-50 p-4">
          <div class="flex items-start gap-3">
            <div class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-orange-100">
              <PhPackage class="size-5 text-orange-600" weight="duotone" />
            </div>
            <div class="min-w-0">
              <p class="truncate text-sm font-semibold text-stone-900">{{ delivery.title }}</p>
              <p class="mt-0.5 text-xs text-stone-500">{{ selectedCourierName(delivery.id) }}</p>
            </div>
          </div>
          <div class="mt-3 flex gap-1">
            <button
              v-for="star in 5"
              :key="star"
              type="button"
              class="rounded p-0.5 text-amber-400 transition hover:scale-110"
              @click="setRating(delivery.id, star)"
            >
              <PhStar class="size-6" :weight="star <= selectedRating(delivery.id) ? 'fill' : 'regular'" />
            </button>
          </div>
          <textarea
            :value="commentByDelivery[delivery.id] || ''"
            rows="2"
            maxlength="500"
            class="input mt-3 min-h-16 resize-none bg-white"
            placeholder="Yorum ekle"
            @input="setComment(delivery.id, $event)"
          />
          <button
            class="btn-primary mt-3 w-full justify-center"
            :disabled="ratingSaving[delivery.id]"
            @click="submitRating(delivery.id)"
          >
            {{ ratingSaving[delivery.id] ? 'Kaydediliyor...' : 'Kuryeyi Puanla' }}
          </button>
          <p v-if="ratingError[delivery.id]" class="mt-2 text-center text-xs font-medium text-red-600">{{ ratingError[delivery.id] }}</p>
        </div>
      </div>
    </div>

    <!-- Loading -->
    <div v-if="store.loading" class="mb-8 flex items-center justify-center py-16">
      <svg class="size-6 animate-spin text-orange-500" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/>
      </svg>
    </div>

    <template v-else-if="store.couriers.length === 0">
      <div class="mb-8 rounded-2xl border border-stone-200 bg-white py-20 text-center">
        <PhTrophy class="mx-auto mb-3 size-12 text-stone-300" weight="duotone" />
        <p class="font-semibold text-stone-900">Henüz kurye yok</p>
        <p class="mt-1 text-sm text-stone-400">Kayıt olan kuryeler burada görünecek</p>
      </div>
    </template>

    <template v-else>
      <!-- Podium -->
      <div v-if="podium" class="mb-8 grid items-end gap-4 sm:grid-cols-3">
        <TopCourierCard :courier="podium.second" :rank="2" />
        <TopCourierCard :courier="podium.first" :rank="1" />
        <TopCourierCard :courier="podium.third" :rank="3" />
      </div>

      <!-- Full Table -->
      <h2 class="mb-4 font-semibold text-stone-900">Tüm Kuryeler</h2>
      <LeaderboardTable :couriers="store.leaderboard" />
    </template>

    <div class="mt-6 flex items-start gap-2.5 rounded-xl border border-stone-200 bg-stone-50 p-4 text-sm text-stone-500">
      <PhChartBar class="mt-0.5 size-5 shrink-0 text-stone-400" weight="duotone" />
      <p>
        <strong class="text-stone-700">Sıralama Nasıl Hesaplanır?</strong> — Kurye puanı, toplam teslimat ve zamanında teslimat oranı birleştirilerek hesaplanır. Her teslimat sonrası anında güncellenir.
      </p>
    </div>
  </div>
</template>
