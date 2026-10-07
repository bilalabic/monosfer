<script setup lang="ts">
import { computed, ref } from 'vue'
import { useCourierStore } from '@/stores/useCourierStore'
import { useDeliveryStore } from '@/stores/useDeliveryStore'
import { useWalletStore } from '@/stores/useWalletStore'
import { PhUsers, PhInfo, PhStar, PhPackage, PhWallet } from '@phosphor-icons/vue'
import { vehicleLabel, vehicleIcon, type VehicleType } from '@/composables/useVehicleMeta'
import type { Courier } from '@/stores/useCourierStore'
import { profileInitials, shortWallet } from '@/utils/profile'

const store = useCourierStore()
const deliveryStore = useDeliveryStore()
const wallet = useWalletStore()
const ratingByDelivery = ref<Record<string, number>>({})
const commentByDelivery = ref<Record<string, string>>({})
const ratingSaving = ref<Record<string, boolean>>({})
const ratingError = ref<Record<string, string>>({})

function vehicle(courier: Courier): VehicleType {
  const type = courier.specialties[0]
  return ['bicycle', 'motorcycle', 'car', 'on_foot'].includes(type || '') ? type as VehicleType : 'on_foot'
}
function bidCount(address: string) {
  return deliveryStore.deliveries.reduce((total, delivery) => total + delivery.bids.filter(bid => bid.courierId.toLowerCase() === address.toLowerCase()).length, 0)
}

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
  <div class="page-shell">
    <page-header eyebrow="Yolları birleştiren insanlar" title="Kurye Dizini" description="Teslimat ağına katılan kuryeleri keşfet. Araçlarını ve teslimatlara verdikleri teklifleri gör.">
      <div class="page-metrics" aria-label="Kurye ağı özeti">
        <div class="page-metric"><strong>{{ store.couriers.length }}</strong><span>Kurye</span></div>
        <div class="page-metric"><strong>{{ deliveryStore.deliveries.reduce((total, d) => total + d.bids.length, 0) }}</strong><span>Toplam teklif</span></div>
      </div>
    </page-header>

    <div class="page-notice">
      <PhInfo class="mt-0.5 size-5 shrink-0" weight="duotone" />
      <p>Bu dizin, zincirde kesinleşmiş tekliflere katılan kuryeleri gösterir. Doğrulanmış puan ve performans sıralaması henüz sunulmuyor.</p>
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
      <div class="mb-4 flex items-center justify-between">
        <h2 class="text-lg font-semibold text-stone-900">Ağdaki kuryeler</h2>
        <span class="text-xs text-stone-500">{{ store.couriers.length }} kişi</span>
      </div>
      <div class="courier-grid">
        <article v-for="courier in store.leaderboard" :key="courier.id" class="courier-profile card bg-white">
          <div class="flex items-center gap-3">
            <div class="courier-profile__avatar" aria-hidden="true">{{ profileInitials(courier.name) }}</div>
            <div class="min-w-0">
              <h3 class="text-base font-semibold leading-snug text-stone-900">{{ courier.name }}</h3>
              <p v-if="courier.specialties.length" class="mt-1 flex items-center gap-1.5 text-xs text-stone-500">
                <component :is="vehicleIcon(vehicle(courier))" class="size-4" weight="duotone" />
                {{ vehicleLabel(vehicle(courier)) }}
              </p>
            </div>
          </div>
          <div class="courier-profile__wallet flex items-center gap-2">
            <PhWallet class="size-4" weight="duotone" />
            <span class="font-mono" :title="courier.walletAddress || courier.id">{{ shortWallet(courier.walletAddress || courier.id) }}</span>
          </div>
          <div class="courier-profile__foot">
            <span><strong class="text-stone-900">{{ bidCount(courier.id) }}</strong> teklif</span>
            <span class="inline-flex items-center gap-1.5"><span class="size-1.5 rounded-full bg-orange-500" />Kesinleşmiş teklif</span>
          </div>
        </article>
      </div>
    </template>

  </div>
</template>
