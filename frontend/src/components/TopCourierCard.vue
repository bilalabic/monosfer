<script setup lang="ts">
import type { Courier } from '@/stores/useCourierStore'
import StarRating from '@/components/StarRating.vue'
import TokenAmount from '@/components/TokenAmount.vue'

const props = defineProps<{ courier: Courier; rank: 1 | 2 | 3 }>()

const config = {
  1: { medal: '🥇', ring: 'ring-2 ring-amber-300', header: 'bg-amber-50 border-amber-200', badge: 'bg-amber-100 text-amber-700 border-amber-300' },
  2: { medal: '🥈', ring: 'ring-2 ring-stone-300', header: 'bg-stone-50 border-stone-200', badge: 'bg-stone-100 text-stone-600 border-stone-300' },
  3: { medal: '🥉', ring: 'ring-2 ring-orange-300', header: 'bg-orange-50 border-orange-200', badge: 'bg-orange-100 text-orange-700 border-orange-300' },
}

const c = config[props.rank]
</script>

<template>
  <div :class="['card card-hover rounded-xl bg-white p-5', rank === 1 ? 'lg:-mt-3 shadow-md' : '']">
    <!-- Header row -->
    <div class="mb-4 flex items-center justify-between">
      <span class="text-2xl">{{ c.medal }}</span>
      <span :class="['rounded-full border px-2 py-0.5 text-xs font-bold', c.badge]">#{{ rank }}</span>
    </div>

    <!-- Avatar + Name -->
    <div class="mb-4 flex items-center gap-3">
      <div :class="['flex size-12 items-center justify-center rounded-xl bg-stone-100 text-sm font-bold text-stone-700', c.ring]">
        {{ courier.avatar }}
      </div>
      <div>
        <p class="font-semibold text-stone-900">{{ courier.name }}</p>
        <StarRating :rating="courier.rating" />
      </div>
    </div>

    <!-- Stats -->
    <div class="mb-4 grid grid-cols-2 gap-2">
      <div class="rounded-lg bg-stone-50 p-3 text-center">
        <p class="text-lg font-bold text-stone-900">{{ courier.totalDeliveries }}</p>
        <p class="text-xs text-stone-400">Teslimat</p>
      </div>
      <div class="rounded-lg bg-stone-50 p-3 text-center">
        <p class="text-lg font-bold text-stone-900">{{ courier.onTimeRate }}%</p>
        <p class="text-xs text-stone-400">Zamanında</p>
      </div>
    </div>

    <!-- Earnings -->
    <div class="rounded-lg border border-stone-100 bg-stone-50 p-3">
      <p class="mb-1 text-xs text-stone-400">Haftalık Kazanç</p>
      <TokenAmount :amount="courier.weeklyEarnings" size="md" />
    </div>

    <!-- Tags -->
    <div class="mt-3 flex flex-wrap gap-1.5">
      <span
        v-for="s in courier.specialties"
        :key="s"
        class="rounded-full border border-stone-200 bg-stone-50 px-2 py-0.5 text-xs text-stone-500"
      >
        {{ s }}
      </span>
    </div>
  </div>
</template>
