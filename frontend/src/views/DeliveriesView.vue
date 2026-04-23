<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { PhMagnifyingGlass as Search, PhPackage, PhLockKey, PhQrCode, PhArrowRight } from '@phosphor-icons/vue'
import { useDeliveryStore } from '@/stores/useDeliveryStore'
import { useWalletStore } from '@/stores/useWalletStore'
import DeliveryCard from '@/components/DeliveryCard.vue'
import BidModal from '@/components/BidModal.vue'

const store = useDeliveryStore()
const wallet = useWalletStore()
const router = useRouter()

type Filter = 'all' | 'open' | 'in_progress' | 'completed'
type LiveScenario = {
  key: 'sender' | 'courier'
  deliveryId: string
  role: string
  title: string
  description: string
  flow: string
  path: string
  iconClass: string
  iconColorClass: string
  borderClass: string
  hoverClass: string
  textClass: string
  flowClass: string
  dotClass: string
}

const filter = ref<Filter>('all')
const search = ref('')
const bidTarget = ref<string | null>(null)

onMounted(() => store.loadDeliveries())

const liveScenarios = computed<LiveScenario[]>(() => {
  const addr = wallet.address.toLowerCase()
  const senderDelivery = store.deliveries.find(d =>
    d.status === 'open' &&
    d.senderId?.toLowerCase() === addr &&
    d.escrowAmount <= 0,
  )
  const courierDelivery = store.deliveries.find(d => d.status === 'in_progress' && d.selectedBidId && d.assignedCourierId === addr)
  const scenarios: LiveScenario[] = []

  if (senderDelivery) {
    scenarios.push({
      key: 'sender',
      deliveryId: senderDelivery.id,
      role: 'Gönderici Akışı',
      title: 'Escrow Ödeme Yap',
      description: `${senderDelivery.title} · ${senderDelivery.escrowAmount || senderDelivery.maxBudget} MON · ${senderDelivery.pickupAddress} → ${senderDelivery.dropoffAddress}`,
      flow: 'Ödeme → İmzala → Blok Onayı → Kilitlendi',
      path: `/payment/${senderDelivery.id}`,
      iconClass: 'bg-orange-100',
      iconColorClass: 'text-orange-500',
      borderClass: 'border-orange-200',
      hoverClass: 'hover:border-orange-400',
      textClass: 'text-orange-500',
      flowClass: 'border-orange-100 bg-orange-50 text-orange-700',
      dotClass: 'bg-orange-400',
    })
  }

  if (courierDelivery) {
    scenarios.push({
      key: 'courier',
      deliveryId: courierDelivery.id,
      role: 'Kurye Akışı',
      title: 'QR ile Ödeme Al',
      description: `${courierDelivery.title} · ${courierDelivery.escrowAmount || courierDelivery.maxBudget} MON · ${courierDelivery.pickupAddress} → ${courierDelivery.dropoffAddress}`,
      flow: 'QR Göster → Onayla → Escrow Serbest → MON Al',
      path: `/courier/receive/${courierDelivery.id}`,
      iconClass: 'bg-green-100',
      iconColorClass: 'text-green-600',
      borderClass: 'border-green-200',
      hoverClass: 'hover:border-green-400',
      textClass: 'text-green-600',
      flowClass: 'border-green-100 bg-green-50 text-green-700',
      dotClass: 'bg-green-500',
    })
  }

  return scenarios
})

function goToScenario(path: string) {
  if (!wallet.connected) {
    router.push('/login')
    return
  }
  router.push(path)
}

const filters: { key: Filter; label: string }[] = [
  { key: 'all', label: 'Tümü' },
  { key: 'open', label: 'Açık' },
  { key: 'in_progress', label: 'Devam Eden' },
  { key: 'completed', label: 'Tamamlanan' },
]

const filtered = computed(() => {
  let list = store.deliveries
  if (filter.value !== 'all') list = list.filter(d => d.status === filter.value)
  if (search.value.trim()) {
    const q = search.value.toLowerCase()
    list = list.filter(d =>
      d.title.toLowerCase().includes(q) ||
      d.pickupAddress.toLowerCase().includes(q) ||
      d.dropoffAddress.toLowerCase().includes(q),
    )
  }
  return list
})
</script>

<template>
  <div class="mx-auto max-w-6xl px-5 py-10 sm:px-8">
    <!-- Header -->
    <div class="mb-7">
      <p class="mb-1 text-xs font-semibold uppercase tracking-widest text-orange-500">Blockchain Güvenceli</p>
      <h1 class="text-2xl font-bold text-stone-900 sm:text-3xl">Aktif Teslimatlar</h1>
      <p class="mt-1 text-stone-500">Kuryeler için açık ilanlar — teklif ver, seçil, kazan</p>
    </div>

    <!-- Canli Senaryo Ozeti -->
    <div v-if="liveScenarios.length > 0" class="mb-8 rounded-2xl border border-purple-200 bg-gradient-to-br from-purple-50 to-orange-50 p-5">
      <div class="mb-4 flex items-center gap-2">
        <span class="rounded-full bg-purple-100 px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-widest text-purple-700">Canlı Senaryolar</span>
        <p class="text-xs text-stone-500">Uygun teslimat kayıtlarından oluşturulan ödeme akışları</p>
      </div>

      <div class="grid gap-3 sm:grid-cols-2">
        <button
          v-for="scenario in liveScenarios"
          :key="scenario.deliveryId"
          :class="[
            'group flex flex-col gap-3 rounded-xl border bg-white p-4 text-left transition hover:shadow-md',
            scenario.borderClass,
            scenario.hoverClass,
          ]"
          @click="goToScenario(scenario.path)"
        >
          <div class="flex items-center justify-between">
            <div :class="['flex size-9 items-center justify-center rounded-xl', scenario.iconClass]">
              <PhLockKey
                v-if="scenario.key === 'sender'"
                :class="['size-5', scenario.iconColorClass]"
                weight="duotone"
              />
              <PhQrCode
                v-else
                :class="['size-5', scenario.iconColorClass]"
                weight="duotone"
              />
            </div>
            <PhArrowRight :class="['size-4 text-stone-300 transition group-hover:translate-x-0.5', scenario.iconColorClass]" weight="bold" />
          </div>
          <div>
            <p :class="['text-xs font-bold uppercase tracking-wide', scenario.textClass]">{{ scenario.role }}</p>
            <p class="mt-0.5 text-sm font-semibold text-stone-900">{{ scenario.title }}</p>
            <p class="mt-1 text-xs leading-relaxed text-stone-500">{{ scenario.description }}</p>
          </div>
          <div :class="['flex items-center gap-2 rounded-lg border px-3 py-1.5', scenario.flowClass]">
            <span :class="['size-1.5 rounded-full', scenario.dotClass]" />
            <span class="text-xs">{{ scenario.flow }}</span>
          </div>
        </button>
      </div>
    </div>

    <!-- Search + Filters -->
    <div class="mb-6 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
      <div class="relative max-w-xs flex-1">
        <Search class="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-stone-400" weight="bold" />
        <input
          v-model="search"
          placeholder="Adres veya başlık ara..."
          class="input pl-10"
        />
      </div>
      <div class="flex items-center gap-1 rounded-xl border border-stone-200 bg-stone-50 p-1">
        <button
          v-for="f in filters"
          :key="f.key"
          :class="[
            'rounded-lg px-3 py-1.5 text-xs font-medium transition-all',
            filter === f.key ? 'bg-white text-stone-900 shadow-sm border border-stone-200' : 'text-stone-500 hover:text-stone-700',
          ]"
          @click="filter = f.key"
        >
          {{ f.label }}
        </button>
      </div>
    </div>

    <p class="mb-4 text-sm text-stone-400">{{ filtered.length }} teslimat</p>

    <div v-if="filtered.length > 0" v-auto-animate class="grid items-stretch gap-5 md:grid-cols-2 xl:grid-cols-3">
      <DeliveryCard
        v-for="d in filtered"
        :key="d.id"
        :delivery="d"
        @bid="bidTarget = $event"
      />
    </div>

    <div v-else class="py-20 text-center">
      <PhPackage class="mx-auto mb-3 size-12 text-stone-300" weight="duotone" />
      <h3 class="font-semibold text-stone-900">Teslimat bulunamadı</h3>
      <p class="mt-1 text-sm text-stone-500">Farklı filtre deneyin</p>
    </div>

    <BidModal
      v-if="bidTarget"
      :delivery-id="bidTarget"
      :max-budget="store.getDelivery(bidTarget)?.maxBudget ?? 0"
      @close="bidTarget = null"
      @success="bidTarget = null"
    />
  </div>
</template>
