<script setup lang="ts">
import { PhCheckCircle as CheckCircle2 } from '@phosphor-icons/vue'
import type { Bid } from '@/stores/useDeliveryStore'
import StarRating from '@/components/StarRating.vue'
import TokenAmount from '@/components/TokenAmount.vue'
import { profileInitials } from '@/utils/profile'

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
    <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
      <div class="flex min-w-0 items-center gap-3">
        <div class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-stone-100 text-sm font-bold text-stone-700">
          {{ bid.courierAvatar || profileInitials(bid.courierName) }}
        </div>
        <div class="min-w-0">
          <div class="flex items-center gap-1.5">
            <span class="text-sm font-semibold text-stone-900">{{ bid.courierName }}</span>
            <CheckCircle2 v-if="isSelected" class="size-4 text-green-500" weight="fill" />
          </div>
          <star-rating v-if="bid.courierRating > 0" :rating="bid.courierRating" class="mt-0.5" />
          <p v-else class="mt-0.5 text-xs text-stone-500">Henüz puanlanmadı</p>
          <p class="mt-1 text-xs text-stone-500"><span v-if="bid.courierDeliveries > 0">{{ bid.courierDeliveries }} teslimat · </span>{{ bid.estimatedTime }}</p>
        </div>
      </div>
      <div class="flex shrink-0 items-center justify-between gap-2 sm:flex-col sm:items-end">
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
