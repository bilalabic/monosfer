<script setup lang="ts">
import { computed, ref } from 'vue'
import { useCourierStore } from '@/stores/useCourierStore'
import { useDeliveryStore } from '@/stores/useDeliveryStore'
import { useWalletStore } from '@/stores/useWalletStore'
import { PhUsers, PhInfo, PhStar, PhPackage, PhUser } from '@phosphor-icons/vue'

const store = useCourierStore()
const deliveryStore = useDeliveryStore()
const wallet = useWalletStore()
const ratingByDelivery = ref<Record<string, number>>({})
const commentByDelivery = ref<Record<string, string>>({})
const ratingSaving = ref<Record<string, boolean>>({})
const ratingError = ref<Record<string, string>>({})

await useAsyncData('couriers-page', async () => {
  await Promise.all([
    store.loadCouriers(),
    deliveryStore.deliveries.length === 0 ? deliveryStore.loadDeliveries() : Promise.resolve(),
  ])
  return true
})

useSeoMeta({
  title: 'Kurye Dizini — Delivera',
  description: 'Finalized teslimat tekliflerinde yer alan kurye cüzdanları.',
})

const pendingRatings = computed(() => {
  const address = wallet.address.toLowerCase()
  if (!address) return []
  return deliveryStore.deliveries.filter(delivery =>
    delivery.chainState === 'Completed' &&
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
      <p class="mb-1 text-xs font-semibold uppercase tracking-widest text-orange-500">Finalized teklif katılımcıları</p>
      <h1 class="flex items-center gap-2 text-2xl font-bold text-stone-900 sm:text-3xl">
        <PhUsers class="size-8 text-orange-500" weight="duotone" />
        Kurye Dizini
      </h1>
      <p class="mt-1 text-stone-500">Finalized zincir projeksiyonlarında teklif vermiş cüzdanlar</p>
    </div>

    <div class="mb-8 flex items-start gap-2.5 rounded-xl border border-blue-200 bg-blue-50 p-4 text-sm text-blue-800">
      <PhInfo class="mt-0.5 size-5 shrink-0" weight="duotone" />
      <p>Backend V2 henüz doğrulanmış itibar veya ödül sıralaması yayınlamıyor. Bu liste yalnızca finalized teklif katılımını gösterir.</p>
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

    <p v-if="store.error" class="mb-6 rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">{{ store.error }}</p>

    <!-- Loading -->
    <div v-if="store.loading" class="mb-8 flex items-center justify-center py-16">
      <svg class="size-6 animate-spin text-orange-500" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/>
      </svg>
    </div>

    <template v-else-if="store.couriers.length === 0">
      <div class="mb-8 rounded-2xl border border-stone-200 bg-white py-20 text-center">
        <PhUsers class="mx-auto mb-3 size-12 text-stone-300" weight="duotone" />
        <p class="font-semibold text-stone-900">Henüz kurye yok</p>
        <p class="mt-1 text-sm text-stone-400">Finalized bir teklifte yer alan cüzdanlar burada görünecek</p>
      </div>
    </template>

    <template v-else>
      <h2 class="mb-4 font-semibold text-stone-900">Teklif Katılımcıları</h2>
      <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <div v-for="courier in store.leaderboard" :key="courier.id" class="card flex items-center gap-3 rounded-xl bg-white p-4">
          <div class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-orange-100 text-orange-700">
            <PhUser class="size-5" weight="duotone" />
          </div>
          <div class="min-w-0">
            <p class="truncate text-sm font-semibold text-stone-900">{{ courier.name }}</p>
            <p class="text-xs text-stone-500">Finalized teklifte görüldü</p>
          </div>
        </div>
      </div>
    </template>

    <div class="mt-6 flex items-start gap-2.5 rounded-xl border border-stone-200 bg-stone-50 p-4 text-sm text-stone-500">
      <PhInfo class="mt-0.5 size-5 shrink-0 text-stone-400" weight="duotone" />
      <p>Kanıtlanmış puan ve performans metrikleri, ilgili V2 ABI/projeksiyonları yayınlandığında bu dizine bağlanabilir.</p>
    </div>
  </div>
</template>
