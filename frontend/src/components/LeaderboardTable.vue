<script setup lang="ts">
import type { Courier } from '@/stores/useCourierStore'
import StarRating from '@/components/StarRating.vue'
import TokenAmount from '@/components/TokenAmount.vue'
import { PhMedal, PhUser } from '@phosphor-icons/vue'

defineProps<{ couriers: Courier[] }>()

const medalColors: Record<number, string> = { 0: 'text-amber-500', 1: 'text-stone-400', 2: 'text-orange-700' }
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
    <div class="divide-y divide-stone-50">
      <div
        v-for="(courier, index) in couriers"
        :key="courier.id"
        class="group relative grid grid-cols-12 items-center gap-4 px-5 py-3.5 transition-all duration-200 ease-out will-change-transform hover:z-10 hover:-translate-y-0.5 hover:bg-stone-50 hover:shadow-sm"
      >
        <div class="col-span-1 flex items-center justify-center sm:justify-start">
          <PhMedal v-if="index < 3" :class="['size-5', medalColors[index]]" weight="fill" />
          <span v-else class="text-sm font-medium text-stone-400">{{ index + 1 }}</span>
        </div>

        <div class="col-span-4 flex items-center gap-2.5">
          <div class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-stone-100 text-stone-600 transition-transform duration-200 ease-out group-hover:scale-105">
            <PhUser class="size-4" weight="duotone" />
          </div>
          <div class="min-w-0">
            <p class="truncate text-sm font-medium text-stone-900">{{ courier.name }}</p>
            <span class="rounded bg-stone-100 px-1.5 py-0.5 text-[10px] text-stone-500">{{ courier.specialties[0] || 'Yeni kurye' }}</span>
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
