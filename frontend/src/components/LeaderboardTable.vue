<script setup lang="ts">
import type { Courier } from '@/stores/useCourierStore'
import StarRating from '@/components/StarRating.vue'
import TokenAmount from '@/components/TokenAmount.vue'

defineProps<{ couriers: Courier[] }>()

const medals: Record<number, string> = { 1: '🥇', 2: '🥈', 3: '🥉' }
</script>

<template>
  <div class="card rounded-xl bg-white overflow-hidden">
    <!-- Header -->
    <div class="grid grid-cols-12 gap-4 border-b border-stone-100 bg-stone-50 px-5 py-3 text-xs font-semibold uppercase tracking-wide text-stone-400">
      <div class="col-span-1">#</div>
      <div class="col-span-4">Kurye</div>
      <div class="col-span-2 text-center">Puan</div>
      <div class="col-span-2 text-center">Teslimat</div>
      <div class="col-span-1 hidden text-center sm:block">%</div>
      <div class="col-span-2 text-right">Kazanç</div>
    </div>

    <!-- Rows -->
    <div v-auto-animate class="divide-y divide-stone-50">
      <div
        v-for="(courier, index) in couriers"
        :key="courier.id"
        class="grid grid-cols-12 items-center gap-4 px-5 py-3.5 transition hover:bg-stone-50"
      >
        <div class="col-span-1">
          <span v-if="index < 3" class="text-base">{{ medals[index + 1] }}</span>
          <span v-else class="text-sm font-medium text-stone-400">{{ index + 1 }}</span>
        </div>

        <div class="col-span-4 flex items-center gap-2.5">
          <div class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-stone-100 text-xs font-bold text-stone-600">
            {{ courier.avatar }}
          </div>
          <div class="min-w-0">
            <p class="truncate text-sm font-medium text-stone-900">{{ courier.name }}</p>
            <span class="rounded bg-stone-100 px-1.5 py-0.5 text-[10px] text-stone-500">{{ courier.specialties[0] }}</span>
          </div>
        </div>

        <div class="col-span-2 flex justify-center">
          <StarRating :rating="courier.rating" />
        </div>

        <div class="col-span-2 text-center text-sm font-medium text-stone-700">
          {{ courier.totalDeliveries }}
        </div>

        <div class="col-span-1 hidden text-center sm:block">
          <span class="text-sm font-medium text-green-600">{{ courier.onTimeRate }}%</span>
        </div>

        <div class="col-span-2 flex justify-end">
          <TokenAmount :amount="courier.weeklyEarnings" size="sm" />
        </div>
      </div>
    </div>
  </div>
</template>
