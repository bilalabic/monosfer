<script setup lang="ts">
import { ref, computed } from 'vue'
import { Search } from 'lucide-vue-next'
import { useDeliveryStore } from '@/stores/useDeliveryStore'
import DeliveryCard from '@/components/DeliveryCard.vue'
import BidModal from '@/components/BidModal.vue'

const store = useDeliveryStore()
type Filter = 'all' | 'open' | 'in_progress' | 'completed'
const filter = ref<Filter>('all')
const search = ref('')
const bidTarget = ref<string | null>(null)

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

    <!-- Search + Filters -->
    <div class="mb-6 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
      <div class="relative max-w-xs flex-1">
        <Search class="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-stone-400" />
        <input
          v-model="search"
          placeholder="Adres veya başlık ara..."
          class="input pl-9"
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

    <div v-if="filtered.length > 0" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <DeliveryCard
        v-for="d in filtered"
        :key="d.id"
        :delivery="d"
        @bid="bidTarget = $event"
      />
    </div>

    <div v-else class="py-20 text-center">
      <div class="mb-3 text-5xl">📦</div>
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
