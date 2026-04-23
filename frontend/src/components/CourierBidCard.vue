<script setup lang="ts">
import { CheckCircle2 } from 'lucide-vue-next'
import type { Bid } from '@/stores/useDeliveryStore'
import StarRating from '@/components/StarRating.vue'
import TokenAmount from '@/components/TokenAmount.vue'

defineProps<{ bid: Bid; isSelected?: boolean; canSelect?: boolean }>()
const emit = defineEmits<{ select: [bidId: string] }>()
</script>

<template>
  <div
    :class="[
      'rounded-xl border p-4 transition-all',
      isSelected ? 'border-green-300 bg-green-50' : 'border-stone-200 bg-white hover:border-stone-300',
    ]"
  >
    <div class="flex items-start justify-between gap-3">
      <div class="flex items-center gap-3">
        <div class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-stone-100 text-sm font-bold text-stone-700">
          {{ bid.courierAvatar }}
        </div>
        <div>
          <div class="flex items-center gap-1.5">
            <span class="text-sm font-semibold text-stone-900">{{ bid.courierName }}</span>
            <CheckCircle2 v-if="isSelected" class="size-4 text-green-500" />
          </div>
          <StarRating :rating="bid.courierRating" class="mt-0.5" />
          <p class="mt-0.5 text-xs text-stone-400">{{ bid.courierDeliveries }} teslimat · {{ bid.estimatedTime }}</p>
        </div>
      </div>
      <div class="flex flex-col items-end gap-2">
        <TokenAmount :amount="bid.tokenAmount" size="md" />
        <span v-if="isSelected" class="text-xs font-medium text-green-600">✓ Seçildi</span>
        <button
          v-else-if="canSelect"
          class="btn-primary py-1 px-3 text-xs"
          @click="emit('select', bid.id)"
        >
          Seç
        </button>
      </div>
    </div>
  </div>
</template>
