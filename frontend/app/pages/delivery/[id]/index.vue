<script setup lang="ts">
import { computed, ref, defineAsyncComponent } from 'vue'
import { PhArrowLeft as ArrowLeft, PhMapPin as MapPin, PhClock as Clock, PhBarbell as Weight, PhPackage as Package, PhShieldCheck as Shield, PhUsers as Users, PhMagnifyingGlass, PhLockKey, PhQrCode, PhStar } from '@phosphor-icons/vue'
import { useDeliveryStore } from '@/stores/useDeliveryStore'
import { useWalletStore } from '@/stores/useWalletStore'
import StatusBadge from '@/components/StatusBadge.vue'
import TokenAmount from '@/components/TokenAmount.vue'
import CourierBidCard from '@/components/CourierBidCard.vue'
import DeliveryTimeline from '@/components/DeliveryTimeline.vue'
import DeliveryEvidencePanel from '@/components/DeliveryEvidencePanel.vue'

// Dynamic import + <ClientOnly> (below): leaflet touches `window` at module load,
// and this page is server-rendered, so the map must never be resolved on the server.
const DeliveryTrackingMap = defineAsyncComponent(() => import('@/components/DeliveryTrackingMap.client.vue'))

const route = useRoute()
const router = useRouter()
const store = useDeliveryStore()
const wallet = useWalletStore()
const delivery = computed(() => store.getDelivery(route.params.id as string))

await useAsyncData('delivery-detail', async () => {
  if (store.deliveries.length === 0) await store.loadDeliveries()
  return true
})

useSeoMeta({
  title: () => delivery.value ? `${delivery.value.title} — Delivera` : 'Teslimat Detayı — Delivera',
  description: () => delivery.value
    ? `${delivery.value.pickupAddress} → ${delivery.value.dropoffAddress} · ${delivery.value.maxBudget} MON`
    : 'Delivera teslimat detayları.',
})

const ratingValue = ref(5)
const ratingComment = ref('')
const ratingSaving = ref(false)
const ratingError = ref('')
const ratingMessage = ref('')
const returnRequesting = ref(false)
const returnError = ref('')

const isOwner = computed(() =>
  !!wallet.address &&
  !!delivery.value?.senderId &&
  wallet.address.toLowerCase() === delivery.value.senderId.toLowerCase()
)
const isAssignedCourier = computed(() =>
  !!wallet.address &&
  !!delivery.value?.assignedCourierId &&
  wallet.address.toLowerCase() === delivery.value.assignedCourierId.toLowerCase()
)
const selectedBid = computed(() => delivery.value?.bids.find(bid => bid.id === delivery.value?.selectedBidId))
const canRate = computed(() => delivery.value?.chainState === 'Completed' && isOwner.value && !delivery.value?.isRated && !!selectedBid.value)
function formatDate(s: string) {
  return new Date(s).toLocaleString('tr-TR', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
}

async function submitRating() {
  if (!delivery.value || ratingSaving.value) return
  ratingSaving.value = true
  ratingError.value = ''
  ratingMessage.value = ''
  try {
    await store.rateDelivery(delivery.value.id, ratingValue.value, ratingComment.value)
    ratingMessage.value = 'Puan kaydedildi.'
  } catch (error) {
    ratingError.value = error instanceof Error ? error.message : 'Puan kaydedilemedi'
  } finally {
    ratingSaving.value = false
  }
}

async function requestReturnAction() {
  if (!delivery.value || returnRequesting.value) return
  returnRequesting.value = true
  returnError.value = ''
  try {
    await store.requestReturn(delivery.value.id)
  } catch (error) {
    returnError.value = error instanceof Error ? error.message : 'İade talebi gönderilemedi'
  } finally {
    returnRequesting.value = false
  }
}
</script>

<template>
  <div v-if="delivery" class="mx-auto max-w-5xl px-5 py-10 sm:px-8">
    <button class="mb-5 flex items-center gap-1.5 text-sm text-stone-500 transition hover:text-stone-900" @click="router.back()">
      <ArrowLeft class="size-4" weight="bold" /> Teslimatlar
    </button>

    <!-- Header -->
    <div class="mb-7 flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
      <div>
        <div class="mb-2 flex items-center gap-3">
          <div class="flex size-9 items-center justify-center rounded-lg bg-orange-100">
            <Package class="size-5 text-orange-600" weight="duotone" />
          </div>
          <h1 class="text-xl font-bold text-stone-900">{{ delivery.title }}</h1>
        </div>
        <div class="flex flex-wrap items-center gap-3">
          <StatusBadge :status="delivery.status" />
          <span class="text-xs text-stone-400">{{ formatDate(delivery.createdAt) }}</span>
        </div>
      </div>
      <div class="flex flex-col items-start sm:items-end gap-1">
        <p class="text-xs text-stone-400">Escrow'daki tutar</p>
        <TokenAmount :amount="delivery.escrowAmount" size="lg" />
      </div>
    </div>

    <div class="grid gap-5 lg:grid-cols-3">
      <!-- Left col -->
      <div class="lg:col-span-2 space-y-4">
        <!-- Route -->
        <div class="card rounded-xl bg-white p-5">
          <p class="mb-4 text-xs font-semibold uppercase tracking-wide text-stone-400">Rota</p>
          <div class="space-y-3">
            <div class="flex items-center gap-3">
              <div class="flex size-7 shrink-0 items-center justify-center rounded-lg bg-green-100"><span class="size-2 rounded-full bg-green-500" /></div>
              <div><p class="text-xs text-stone-400">Alış</p><p class="text-sm font-medium text-stone-900">{{ delivery.pickupAddress }}</p></div>
            </div>
            <div class="ml-3.5 h-4 w-px bg-stone-200" />
            <div class="flex items-center gap-3">
              <div class="flex size-7 shrink-0 items-center justify-center rounded-lg bg-red-100"><span class="size-2 rounded-full bg-red-400" /></div>
              <div><p class="text-xs text-stone-400">Teslim</p><p class="text-sm font-medium text-stone-900">{{ delivery.dropoffAddress }}</p></div>
            </div>
          </div>
        </div>

        <!-- Info grid -->
        <div class="grid grid-cols-3 gap-3">
          <div class="card rounded-xl bg-white p-4 text-center">
            <MapPin class="mx-auto mb-1.5 size-5 text-stone-400" weight="fill" />
            <p class="text-sm font-bold text-stone-900">{{ delivery.distance }}</p>
            <p class="text-xs text-stone-400">Mesafe</p>
          </div>
          <div class="card rounded-xl bg-white p-4 text-center">
            <Weight class="mx-auto mb-1.5 size-5 text-stone-400" weight="fill" />
            <p class="text-sm font-bold text-stone-900">{{ delivery.weight }}</p>
            <p class="text-xs text-stone-400">Ağırlık</p>
          </div>
          <div class="card rounded-xl bg-white p-4 text-center">
            <Clock class="mx-auto mb-1.5 size-5 text-stone-400" weight="fill" />
            <p class="text-sm font-bold text-stone-900">{{ new Date(delivery.deadline).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' }) }}</p>
            <p class="text-xs text-stone-400">Son Saat</p>
          </div>
        </div>

        <!-- Description -->
        <div v-if="delivery.description" class="card rounded-xl bg-white p-5">
          <p class="mb-2 text-xs font-semibold uppercase tracking-wide text-stone-400">Açıklama</p>
          <p class="text-sm leading-relaxed text-stone-600">{{ delivery.description }}</p>
        </div>

        <!-- Bids -->
        <div class="card rounded-xl bg-white p-5">
          <p class="mb-4 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-stone-400">
            <Users class="size-4" weight="fill" /> Teklifler ({{ delivery.bids.length }})
          </p>
          <div v-if="delivery.bids.length > 0" class="space-y-3">
            <CourierBidCard
              v-for="bid in delivery.bids"
              :key="bid.id"
              :bid="bid"
              :is-selected="delivery.selectedBidId === bid.id"
              :can-select="delivery.status === 'open' && isOwner"
              @select="store.selectBid(delivery!.id, $event)"
            />
          </div>
          <div v-else class="py-8 text-center">
            <p class="text-3xl mb-2">⏳</p>
            <p class="text-sm text-stone-500">Henüz teklif yok.</p>
          </div>
        </div>
      </div>

      <!-- Right col -->
      <div class="space-y-4">
        <!-- Timeline -->
        <div class="card rounded-xl bg-white p-5">
          <p class="mb-5 text-xs font-semibold uppercase tracking-wide text-stone-400">Teslimat Süreci</p>
          <DeliveryTimeline :timeline="delivery.timeline" />
        </div>

        <!-- Explicit import bypasses Nuxt's filename-based .client.vue SSR skip, and
             leaflet touches `window` at module load — ClientOnly is the real guard. -->
        <ClientOnly>
          <DeliveryTrackingMap
            :key="delivery.id"
            :delivery-id="delivery.id"
            :chain-state="delivery.chainState"
            :is-owner="isOwner"
            :is-assigned-courier="isAssignedCourier"
            :courier-name="selectedBid?.courierName"
          />
        </ClientOnly>

        <DeliveryEvidencePanel
          v-if="isOwner || isAssignedCourier"
          :key="`evidence-${delivery.id}`"
          :delivery-id="delivery.id"
          :chain-state="delivery.chainState"
        />

        <div v-if="isOwner && delivery.chainState === 'ReadyForPickup' && selectedBid" class="card rounded-xl bg-white p-5">
          <p class="mb-2 text-xs font-semibold uppercase tracking-wide text-stone-400">Teslim Alma Onayı</p>
          <p class="text-sm font-semibold text-stone-900">{{ selectedBid.courierName }} için süreli EIP-712 kabul paketi oluşturun</p>
          <p class="mt-1 text-xs leading-relaxed text-stone-500">İmza URL'ye veya tarayıcı depolamasına yazılmaz; paketi doğrudan atanmış kuryeye iletin.</p>
          <button class="btn-primary mt-4 w-full justify-center" @click="router.push(`/delivery/${delivery.id}/confirm`)">
            Kabul Paketini Oluştur
          </button>
        </div>

        <div v-if="canRate || delivery.isRated" class="card rounded-xl bg-white p-5">
          <p class="mb-2 text-xs font-semibold uppercase tracking-wide text-stone-400">Kurye Puanı</p>
          <template v-if="delivery.isRated">
            <div class="flex items-center gap-1.5 text-amber-500">
              <PhStar v-for="star in 5" :key="star" class="size-5" :weight="star <= (delivery.rating || 0) ? 'fill' : 'regular'" />
            </div>
            <p class="mt-2 text-sm font-semibold text-stone-900">{{ selectedBid?.courierName || 'Kurye' }} puanlandı</p>
          </template>
          <template v-else>
            <p class="text-sm font-semibold text-stone-900">{{ selectedBid?.courierName }} için puan ver</p>
            <div class="mt-3 flex gap-1">
              <button
                v-for="star in 5"
                :key="star"
                type="button"
                class="rounded p-0.5 text-amber-400 transition hover:scale-110"
                @click="ratingValue = star"
              >
                <PhStar class="size-7" :weight="star <= ratingValue ? 'fill' : 'regular'" />
              </button>
            </div>
            <textarea
              v-model="ratingComment"
              rows="3"
              class="input mt-3 min-h-20 resize-none"
              maxlength="500"
              placeholder="Kısa yorum yazabilirsiniz"
            />
            <button class="btn-primary mt-3 w-full justify-center" :disabled="ratingSaving" @click="submitRating">
              {{ ratingSaving ? 'Kaydediliyor...' : 'Puanı Kaydet' }}
            </button>
            <p v-if="ratingMessage" class="mt-2 text-center text-xs font-medium text-green-600">{{ ratingMessage }}</p>
            <p v-if="ratingError" class="mt-2 text-center text-xs font-medium text-red-600">{{ ratingError }}</p>
          </template>
        </div>

        <!-- Escrow badge -->
        <div class="rounded-xl border border-orange-200 bg-orange-50 p-5">
          <div class="mb-2 flex items-center gap-2">
            <Shield class="size-5 text-orange-600" weight="duotone" />
            <p class="text-sm font-semibold text-orange-700">Escrow Güvencesi</p>
          </div>
          <p class="text-xs leading-relaxed text-stone-600">
            Ödemeniz teslimat tamamlanana kadar akıllı sözleşmede bekler. Hiç kimse tek başına dokunamaz.
          </p>
          <div class="mt-3 rounded-lg bg-white border border-orange-100 p-2.5 text-center">
            <TokenAmount :amount="delivery.escrowAmount" size="sm" />
            <p class="mt-0.5 text-xs text-stone-400">Kilitli</p>
          </div>
        </div>

        <!-- Action buttons -->
        <template v-if="wallet.connected">
          <button
            v-if="delivery.chainState === 'AwaitingFunding' && isOwner && !delivery.customerFunded"
            class="btn-primary w-full justify-center"
            @click="router.push(`/payment/${delivery.id}`)"
          >
            <PhLockKey class="size-4" weight="bold" />
            Ödemeyi Kilitle (Escrow)
          </button>
          <div
            v-else-if="delivery.chainState === 'AwaitingFunding' && isOwner && delivery.customerFunded"
            class="flex w-full items-center justify-center gap-2 rounded-xl border border-green-200 bg-green-50 px-4 py-3 text-sm font-semibold text-green-700"
          >
            <PhLockKey class="size-4" weight="bold" />
            Ödeme Escrow'da Kilitli
          </div>
          <button
            v-if="['AwaitingFunding', 'ReadyForPickup', 'InTransit', 'DeliveredPending'].includes(delivery.chainState) && delivery.selectedBidId && isAssignedCourier"
            class="w-full justify-center rounded-xl border border-orange-200 bg-orange-50 px-4 py-3 flex items-center gap-2 text-sm font-semibold text-orange-700 hover:bg-orange-100 transition"
            @click="router.push(`/courier/receive/${delivery.id}`)"
          >
            <PhQrCode class="size-4" weight="bold" />
            Kurye Teslimat Akışı
          </button>
          <div v-if="delivery.chainState === 'InTransit' && (isOwner || isAssignedCourier)" class="space-y-1.5">
            <button
              class="w-full justify-center rounded-xl border border-red-200 bg-red-50 px-4 py-3 flex items-center gap-2 text-sm font-semibold text-red-700 hover:bg-red-100 transition disabled:opacity-60"
              :disabled="returnRequesting"
              @click="requestReturnAction"
            >
              {{ returnRequesting ? 'Gönderiliyor...' : 'İade Talep Et' }}
            </button>
            <p v-if="returnError" class="text-center text-xs font-medium text-red-600">{{ returnError }}</p>
          </div>
          <div v-if="isOwner && delivery.chainState === 'ReturnRequired'" class="card rounded-xl bg-white p-5">
            <p class="mb-2 text-xs font-semibold uppercase tracking-wide text-stone-400">İade Onayı</p>
            <p class="text-sm text-stone-600">Kuryenin iadeyi teslim almasını onaylamak için süreli EIP-712 kabul paketi oluşturun.</p>
            <button class="btn-primary mt-4 w-full justify-center" @click="router.push(`/delivery/${delivery.id}/confirm`)">
              İade Kabul Paketini Oluştur
            </button>
          </div>
        </template>
      </div>
    </div>
  </div>

  <div v-else-if="store.loading" class="flex min-h-[50vh] items-center justify-center">
    <svg class="size-6 animate-spin text-orange-500" fill="none" viewBox="0 0 24 24">
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/>
    </svg>
  </div>

  <div v-else class="flex min-h-[50vh] flex-col items-center justify-center gap-3">
    <PhMagnifyingGlass class="size-12 text-stone-300" weight="duotone" />
    <h2 class="font-semibold text-stone-900">Teslimat bulunamadı</h2>
    <p v-if="store.error" class="text-sm text-red-600">{{ store.error }}</p>
    <button class="btn-primary" @click="router.push('/deliveries')">
      <ArrowLeft class="size-4" weight="bold" /> Teslimatlar
    </button>
  </div>
</template>
