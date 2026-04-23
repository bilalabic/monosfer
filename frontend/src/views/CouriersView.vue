<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { useCourierStore } from '@/stores/useCourierStore'
import TopCourierCard from '@/components/TopCourierCard.vue'
import LeaderboardTable from '@/components/LeaderboardTable.vue'
import { PhTrophy, PhMedal, PhChartBar } from '@phosphor-icons/vue'

const store = useCourierStore()

onMounted(() => store.loadCouriers())

const podium = computed(() => {
  const [first, second, third] = store.topThree
  if (!first || !second || !third) return null
  return { first, second, third }
})
</script>

<template>
  <div class="mx-auto max-w-6xl px-5 py-10 sm:px-8">
    <div class="mb-8">
      <p class="mb-1 text-xs font-semibold uppercase tracking-widest text-orange-500">Haftalık Sıralama</p>
      <h1 class="flex items-center gap-2 text-2xl font-bold text-stone-900 sm:text-3xl">
        <PhTrophy class="size-8 text-orange-500" weight="duotone" />
        Kurye Liderlik Tablosu
      </h1>
      <p class="mt-1 text-stone-500">Her pazar gecesi ödüller akıllı sözleşme tarafından otomatik dağıtılır</p>
    </div>

    <!-- Prize Pool -->
    <div class="mb-8 rounded-xl border border-amber-200 bg-amber-50 p-5">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <p class="text-xs font-semibold text-amber-600">Bu Haftanın Ödül Havuzu</p>
          <p class="mt-1 text-3xl font-extrabold text-stone-900">2,400 DLV</p>
        </div>
        <div class="flex gap-6 text-center text-sm">
          <div>
            <p class="text-lg font-bold text-amber-600">1,200</p>
            <p class="flex items-center justify-center gap-1 text-xs text-stone-500">
              <PhMedal class="size-4 text-amber-500" weight="fill" /> 1. Sıra
            </p>
          </div>
          <div>
            <p class="text-lg font-bold text-stone-500">720</p>
            <p class="flex items-center justify-center gap-1 text-xs text-stone-500">
              <PhMedal class="size-4 text-stone-400" weight="fill" /> 2. Sıra
            </p>
          </div>
          <div>
            <p class="text-lg font-bold text-orange-500">480</p>
            <p class="flex items-center justify-center gap-1 text-xs text-stone-500">
              <PhMedal class="size-4 text-orange-700" weight="fill" /> 3. Sıra
            </p>
          </div>
        </div>
      </div>
    </div>

    <!-- Loading -->
    <div v-if="store.loading" class="mb-8 flex items-center justify-center py-16">
      <svg class="size-6 animate-spin text-orange-500" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/>
      </svg>
    </div>

    <template v-else-if="store.couriers.length === 0">
      <div class="mb-8 rounded-2xl border border-stone-200 bg-white py-20 text-center">
        <PhTrophy class="mx-auto mb-3 size-12 text-stone-300" weight="duotone" />
        <p class="font-semibold text-stone-900">Henüz kurye yok</p>
        <p class="mt-1 text-sm text-stone-400">Kayıt olan kuryeler burada görünecek</p>
      </div>
    </template>

    <template v-else>
      <!-- Podium -->
      <div v-if="podium" class="mb-8 grid items-end gap-4 sm:grid-cols-3">
        <TopCourierCard :courier="podium.second" :rank="2" />
        <TopCourierCard :courier="podium.first" :rank="1" />
        <TopCourierCard :courier="podium.third" :rank="3" />
      </div>

      <!-- Full Table -->
      <h2 class="mb-4 font-semibold text-stone-900">Tüm Kuryeler</h2>
      <LeaderboardTable :couriers="store.leaderboard" />
    </template>

    <div class="mt-6 flex items-start gap-2.5 rounded-xl border border-stone-200 bg-stone-50 p-4 text-sm text-stone-500">
      <PhChartBar class="mt-0.5 size-5 shrink-0 text-stone-400" weight="duotone" />
      <p>
        <strong class="text-stone-700">Sıralama Nasıl Hesaplanır?</strong> — Kurye puanı, toplam teslimat ve zamanında teslimat oranı birleştirilerek hesaplanır. Her teslimat sonrası anında güncellenir.
      </p>
    </div>
  </div>
</template>
