<script setup lang="ts">
import { ref, computed } from 'vue'
import { PhMagnifyingGlass as Search, PhPackage, PhLockKey, PhQrCode, PhArrowRight } from '@phosphor-icons/vue'
import { useDeliveryStore } from '@/stores/useDeliveryStore'
import { useWalletStore } from '@/stores/useWalletStore'
import DeliveryCard from '@/components/DeliveryCard.vue'
import BidModal from '@/components/BidModal.vue'

const store = useDeliveryStore()
const wallet = useWalletStore()
const router = useRouter()

type Filter = 'all' | 'open' | 'in_progress' | 'terminal'
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

await useAsyncData('deliveries-list', async () => {
  await store.loadDeliveries()
  return true
})

useSeoMeta({
  title: 'Aktif Teslimatlar — Delivera',
  description: 'Merkeziyetsiz teslimat ağında açık ilanlar — kuryeler için teklif verme ve blockchain escrow ile güvenli ödeme.',
})

const liveScenarios = computed<LiveScenario[]>(() => {
  const addr = wallet.address.toLowerCase()
  const senderDelivery = store.deliveries.find(d =>
    d.chainState === 'AwaitingFunding' &&
    d.senderId?.toLowerCase() === addr &&
    !d.customerFunded,
  )
  const courierDelivery = store.deliveries.find(d => ['AwaitingFunding', 'ReadyForPickup', 'InTransit', 'DeliveredPending'].includes(d.chainState) && d.selectedBidId && d.assignedCourierId === addr)
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
  { key: 'all', label: 'Aktif' },
  { key: 'open', label: 'Açık' },
  { key: 'in_progress', label: 'Devam Eden' },
  { key: 'terminal', label: 'Sonuçlanan' },
]

const terminalStatuses = ['completed', 'returned', 'resolved', 'cancelled', 'expired']
function filterCount(key: Filter) {
  return store.deliveries.filter(d => key === 'all' ? !terminalStatuses.includes(d.status)
    : key === 'terminal' ? terminalStatuses.includes(d.status) : d.status === key).length
}

const filtered = computed(() => {
  let list = store.deliveries
  if (filter.value === 'all') {
    list = list.filter(d => !terminalStatuses.includes(d.status))
  } else if (filter.value === 'terminal') {
    list = list.filter(d => terminalStatuses.includes(d.status))
  } else {
    list = list.filter(d => d.status === filter.value)
  }
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
  <div class="page-shell">
    <!-- Header -->
    <page-header eyebrow="Bir paket. Yeni bir yolculuk." title="Aktif Teslimatlar" description="Sana uygun teslimatı bul. Teklifini ver, güvenle yola çık.">
      <div class="page-metrics" aria-label="Teslimat özeti">
        <div class="page-metric"><strong>{{ filterCount('open') }}</strong><span>Açık ilan</span></div>
        <div class="page-metric"><strong>{{ filterCount('in_progress') }}</strong><span>Devam eden</span></div>
        <div class="page-metric"><strong>{{ store.deliveries.length }}</strong><span>Toplam teslimat</span></div>
      </div>
    </page-header>

    <!-- Canli Senaryo Ozeti -->
    <div v-if="liveScenarios.length > 0" class="scenario-panel">
      <div class="mb-4 flex items-center gap-2">
        <span class="rounded-full bg-orange-100 px-2.5 py-1 text-[10px] font-bold uppercase tracking-widest text-orange-800">Sıradaki adımın</span>
        <p class="text-xs text-stone-500">İşlem bekleyen teslimatların</p>
      </div>

      <div class="scenario-grid">
        <button
          v-for="scenario in liveScenarios"
          :key="scenario.deliveryId"
          :class="[
            'scenario-action group rounded-xl border bg-white p-4 text-left transition hover:shadow-md',
            scenario.borderClass,
            scenario.hoverClass,
          ]"
          @click="goToScenario(scenario.path)"
        >
          <div class="scenario-action__icon">
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
          <div :class="['scenario-action__flow flex items-center gap-2 rounded-lg border px-3 py-1.5', scenario.flowClass]">
            <span :class="['size-1.5 rounded-full', scenario.dotClass]" />
            <span class="text-xs">{{ scenario.flow }}</span>
          </div>
        </button>
      </div>
    </div>

    <!-- Search + Filters -->
    <div class="page-toolbar">
      <div class="page-search">
        <Search class="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-stone-400" weight="bold" />
        <input
          v-model="search"
          aria-label="Teslimat ara"
          placeholder="Adres veya başlık ara..."
          class="input pl-10"
        />
      </div>
      <div class="page-tabs" role="group" aria-label="Teslimat durumları">
        <button
          v-for="f in filters"
          :key="f.key"
          class="page-tab"
          :aria-pressed="filter === f.key"
          @click="filter = f.key"
        >
          {{ f.label }}
          <span class="page-tab__count">{{ filterCount(f.key) }}</span>
        </button>
      </div>
    </div>

    <p v-if="store.error" class="mb-4 rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">{{ store.error }}</p>

    <p class="mb-4 text-sm text-stone-400">{{ filtered.length }} teslimat</p>

    <div v-if="filtered.length > 0" v-auto-animate class="grid items-stretch gap-5 md:grid-cols-2 xl:grid-cols-3">
      <delivery-card
        v-for="d in filtered"
        :key="d.id"
        :delivery="d"
        @bid="bidTarget = $event"
      />
    </div>

    <div v-else class="page-empty">
      <PhPackage class="mx-auto mb-3 size-12 text-stone-300" weight="duotone" />
      <h3 class="font-semibold text-stone-900">Teslimat bulunamadı</h3>
      <p class="mt-1 text-sm text-stone-500">Farklı filtre deneyin</p>
    </div>

    <bid-modal
      v-if="bidTarget"
      :delivery-id="bidTarget"
      :max-budget="store.getDelivery(bidTarget)?.maxBudget ?? 0"
      @close="bidTarget = null"
      @success="bidTarget = null"
    />
  </div>
</template>
