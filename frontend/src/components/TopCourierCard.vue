<script setup lang="ts">
import type { Courier } from '@/stores/useCourierStore'
import StarRating from '@/components/StarRating.vue'
import TokenAmount from '@/components/TokenAmount.vue'
import { PhCrown, PhStar } from '@phosphor-icons/vue'

const props = defineProps<{ courier: Courier; rank: 1 | 2 | 3 }>()

const config = {
  1: {
    wrapClass: 'order-2 sm:order-1',
    cardClass: 'border-amber-200 shadow-amber-100 shadow-xl ring-1 ring-amber-200',
    headerGrad: 'from-amber-400 to-orange-400',
    avatarRing: 'ring-4 ring-white/60',
    avatarBg: 'bg-amber-100 text-amber-800',
    rankBadge: 'bg-amber-400 text-white',
    platform: 'h-3 bg-gradient-to-r from-amber-400 to-orange-400 rounded-b-xl mx-4',
    label: '1. Sıra',
    prize: '1,200 MON',
    prizeColor: 'text-amber-600',
    statBg: 'bg-amber-50',
  },
  2: {
    wrapClass: 'order-1 sm:order-0',
    cardClass: 'border-slate-200 shadow-slate-100 shadow-md ring-1 ring-slate-200',
    headerGrad: 'from-slate-400 to-slate-500',
    avatarRing: 'ring-4 ring-white/60',
    avatarBg: 'bg-slate-100 text-slate-700',
    rankBadge: 'bg-slate-400 text-white',
    platform: 'h-1.5 bg-gradient-to-r from-slate-300 to-slate-400 rounded-b-xl mx-4',
    label: '2. Sıra',
    prize: '720 MON',
    prizeColor: 'text-slate-500',
    statBg: 'bg-slate-50',
  },
  3: {
    wrapClass: 'order-3 sm:order-2',
    cardClass: 'border-orange-200 shadow-orange-100 shadow-md ring-1 ring-orange-200',
    headerGrad: 'from-orange-600 to-orange-700',
    avatarRing: 'ring-4 ring-white/60',
    avatarBg: 'bg-orange-100 text-orange-800',
    rankBadge: 'bg-orange-700 text-white',
    platform: 'h-1 bg-gradient-to-r from-orange-500 to-orange-600 rounded-b-xl mx-4',
    label: '3. Sıra',
    prize: '480 MON',
    prizeColor: 'text-orange-600',
    statBg: 'bg-orange-50',
  },
}

const c = config[props.rank]
</script>

<template>
  <div :class="['flex flex-col', c.wrapClass, rank === 1 ? 'sm:-mt-4' : 'sm:mt-4']">
    <div :class="['card rounded-xl bg-white border overflow-hidden transition-all duration-200 ease-out will-change-transform hover:-translate-y-1 hover:shadow-xl', c.cardClass]">
      <!-- Gradient header -->
      <div :class="['relative flex flex-col items-center py-5 bg-gradient-to-br', c.headerGrad]">
        <!-- Crown for rank 1 -->
        <div v-if="rank === 1" class="mb-1">
          <PhCrown class="size-5 text-white/90 drop-shadow" weight="fill" />
        </div>
        <!-- Rank badge -->
        <span :class="['absolute top-2.5 right-2.5 rounded-full px-2 py-0.5 text-xs font-bold', c.rankBadge]">
          {{ c.label }}
        </span>
        <!-- Avatar -->
        <div :class="[
          'flex items-center justify-center rounded-2xl text-lg font-bold shadow-md',
          c.avatarBg, c.avatarRing,
          rank === 1 ? 'size-16' : 'size-13'
        ]">
          {{ courier.avatar }}
        </div>
        <!-- Name + star -->
        <p class="mt-2.5 font-bold text-white text-sm drop-shadow">{{ courier.name }}</p>
        <div class="mt-1 flex items-center gap-1">
          <PhStar class="size-3.5 text-white/80" weight="fill" />
          <span class="text-xs text-white/90 font-medium">{{ courier.rating }}</span>
        </div>
      </div>

      <!-- Body -->
      <div class="p-4">
        <!-- Stats row -->
        <div class="mb-3 grid grid-cols-2 gap-2">
          <div :class="['rounded-lg p-2.5 text-center', c.statBg]">
            <p class="text-base font-bold text-stone-900">{{ courier.totalDeliveries }}</p>
            <p class="text-[10px] text-stone-400 mt-0.5">Teslimat</p>
          </div>
          <div :class="['rounded-lg p-2.5 text-center', c.statBg]">
            <p class="text-base font-bold text-green-600">{{ courier.onTimeRate }}%</p>
            <p class="text-[10px] text-stone-400 mt-0.5">Zamanında</p>
          </div>
        </div>

        <!-- Earnings -->
        <div class="rounded-lg border border-stone-100 bg-stone-50 px-3 py-2 flex items-center justify-between">
          <span class="text-xs text-stone-400">Haftalık Kazanç</span>
          <TokenAmount :amount="courier.weeklyEarnings" size="sm" />
        </div>

        <!-- Prize -->
        <div class="mt-2.5 text-center">
          <span class="text-xs font-semibold tracking-wide uppercase" :class="c.prizeColor">
            Ödül: {{ c.prize }}
          </span>
        </div>

        <!-- Specialties -->
        <div class="mt-2 flex flex-wrap gap-1 justify-center">
          <span
            v-for="s in courier.specialties.slice(0, 2)"
            :key="s"
            class="rounded-full border border-stone-200 bg-stone-50 px-2 py-0.5 text-[10px] text-stone-500"
          >
            {{ s }}
          </span>
        </div>
      </div>
    </div>
    <!-- Podium platform bar -->
    <div :class="c.platform" />
  </div>
</template>
