<script setup lang="ts">
import { RouterLink } from 'vue-router'
import { MapPin, Clock, Weight, Package, ChevronRight } from 'lucide-vue-next'
import type { Delivery } from '@/stores/useDeliveryStore'
import StatusBadge from '@/components/StatusBadge.vue'
import TokenAmount from '@/components/TokenAmount.vue'

const props = defineProps<{ delivery: Delivery }>()
const emit = defineEmits<{ bid: [deliveryId: string] }>()

function formatTime(dateStr: string) {
  return new Date(dateStr).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' })
}
</script>

<template>
  <div class="card card-hover rounded-xl bg-white p-5">
    <!-- Header -->
    <div class="mb-4 flex items-start justify-between gap-3">
      <div class="flex items-center gap-3">
        <div class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-orange-100">
          <Package class="size-4 text-orange-600" />
        </div>
        <div>
          <h3 class="text-sm font-semibold text-stone-900 leading-tight">{{ delivery.title }}</h3>
          <p class="text-xs text-stone-400 mt-0.5">{{ formatTime(delivery.createdAt) }} · {{ delivery.bids.length }} teklif</p>
        </div>
      </div>
      <StatusBadge :status="delivery.status" />
    </div>

    <!-- Route -->
    <div class="mb-4 rounded-lg border border-stone-100 bg-stone-50 p-3 space-y-2">
      <div class="flex items-center gap-2 text-xs">
        <span class="size-1.5 rounded-full bg-green-500 shrink-0" />
        <span class="text-stone-600 truncate">{{ delivery.pickupAddress }}</span>
      </div>
      <div class="ml-[3px] h-3 w-px bg-stone-300" />
      <div class="flex items-center gap-2 text-xs">
        <span class="size-1.5 rounded-full bg-red-400 shrink-0" />
        <span class="text-stone-600 truncate">{{ delivery.dropoffAddress }}</span>
      </div>
    </div>

    <!-- Meta -->
    <div class="mb-4 flex flex-wrap gap-3 text-xs text-stone-400">
      <span class="flex items-center gap-1"><MapPin class="size-3" />{{ delivery.distance }}</span>
      <span class="flex items-center gap-1"><Weight class="size-3" />{{ delivery.weight }}</span>
      <span class="flex items-center gap-1"><Clock class="size-3" />{{ formatTime(delivery.deadline) }}'e kadar</span>
    </div>

    <!-- Budget & Actions -->
    <div class="flex items-center justify-between">
      <div>
        <p class="text-xs text-stone-400 mb-0.5">Maks. bütçe</p>
        <TokenAmount :amount="delivery.maxBudget" size="md" />
      </div>
      <div class="flex items-center gap-2">
        <button
          v-if="delivery.status === 'open'"
          class="btn-primary py-1.5 px-3 text-xs"
          @click="emit('bid', delivery.id)"
        >
          Teklif Ver
        </button>
        <RouterLink
          :to="`/delivery/${delivery.id}`"
          class="flex items-center gap-1 rounded-lg border border-stone-200 bg-stone-50 px-3 py-1.5 text-xs font-medium text-stone-600 transition hover:bg-stone-100"
        >
          Detay <ChevronRight class="size-3" />
        </RouterLink>
      </div>
    </div>
  </div>
</template>
