<script setup lang="ts">
import { useCourierStore } from '@/stores/useCourierStore'
import TopCourierCard from '@/components/TopCourierCard.vue'
import LeaderboardTable from '@/components/LeaderboardTable.vue'

const store = useCourierStore()
</script>

<template>
  <div class="mx-auto max-w-6xl px-5 py-10 sm:px-8">
    <div class="mb-8">
      <p class="mb-1 text-xs font-semibold uppercase tracking-widest text-orange-500">Haftalık Sıralama</p>
      <h1 class="text-2xl font-bold text-stone-900 sm:text-3xl">🏆 Kurye Liderlik Tablosu</h1>
      <p class="mt-1 text-stone-500">Her pazar gecesi ödüller akıllı sözleşme tarafından otomatik dağıtılır</p>
    </div>

    <!-- Prize Pool -->
    <div class="mb-8 rounded-xl border border-amber-200 bg-amber-50 p-5">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <p class="text-xs font-semibold text-amber-600">Bu Haftanın Ödül Havuzu</p>
          <p class="mt-1 text-3xl font-extrabold text-stone-900">2,400 MON</p>
        </div>
        <div class="flex gap-6 text-center text-sm">
          <div>
            <p class="text-lg font-bold text-amber-600">1,200</p>
            <p class="text-xs text-stone-500">🥇 1. Sıra</p>
          </div>
          <div>
            <p class="text-lg font-bold text-stone-500">720</p>
            <p class="text-xs text-stone-500">🥈 2. Sıra</p>
          </div>
          <div>
            <p class="text-lg font-bold text-orange-500">480</p>
            <p class="text-xs text-stone-500">🥉 3. Sıra</p>
          </div>
        </div>
      </div>
    </div>

    <!-- Podium -->
    <div class="mb-8 grid gap-4 sm:grid-cols-3">
      <div class="sm:order-1"><TopCourierCard :courier="store.topThree[1]" :rank="2" /></div>
      <div class="sm:order-0"><TopCourierCard :courier="store.topThree[0]" :rank="1" /></div>
      <div class="sm:order-2"><TopCourierCard :courier="store.topThree[2]" :rank="3" /></div>
    </div>

    <!-- Full Table -->
    <h2 class="mb-4 font-semibold text-stone-900">Tüm Kuryeler</h2>
    <LeaderboardTable :couriers="store.leaderboard" />

    <div class="mt-6 rounded-xl border border-stone-200 bg-stone-50 p-4 text-sm text-stone-500">
      📊 <strong class="text-stone-700">Sıralama Nasıl Hesaplanır?</strong> — Kurye puanı, toplam teslimat ve zamanında teslimat oranı birleştirilerek hesaplanır. Her teslimat sonrası anında güncellenir.
    </div>
  </div>
</template>
