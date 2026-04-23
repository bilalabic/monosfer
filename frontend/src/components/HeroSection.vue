<script setup lang="ts">
import { RouterLink } from 'vue-router'
import { ArrowRight, Shield, Zap, Trophy } from 'lucide-vue-next'

const features = [
  { icon: Shield, label: 'Escrow Güvenceli' },
  { icon: Zap, label: 'Monad Blockchain' },
  { icon: Trophy, label: 'Liderlik Tablosu' },
]
</script>

<template>
  <section class="px-5 pt-14 pb-20 sm:px-8">
    <div class="mx-auto max-w-6xl">
      <!-- Badge -->
      <div class="mb-6 inline-flex items-center gap-2 rounded-full border border-orange-200 bg-orange-50 px-3.5 py-1.5 text-xs font-medium text-orange-700">
        <span class="size-1.5 rounded-full bg-orange-500 animate-pulse-dot" />
        Monad Hackathon 2026 · Merkeziyetsiz Teslimat
      </div>

      <div class="grid gap-12 lg:grid-cols-2 lg:items-center">
        <!-- Left -->
        <div>
          <h1 class="mb-5 text-4xl font-extrabold leading-tight tracking-tight text-stone-900 sm:text-5xl">
            Teslimatı güvenli,<br />
            <span class="gradient-text">ücretlendirmeyi adil</span><br />
            hale getiriyoruz.
          </h1>
          <p class="mb-8 text-base leading-relaxed text-stone-500">
            Kuryeler kendi fiyatlarını belirler, müşteriler puana göre seçer.
            Ödeme akıllı sözleşmede kilitli — teslim edilene kadar hiç kimse dokunamaz.
          </p>
          <div class="flex flex-col gap-3 sm:flex-row">
            <RouterLink to="/deliveries" class="btn-primary text-center justify-center sm:justify-start">
              Teslimatları Gör
              <ArrowRight class="size-4" />
            </RouterLink>
            <RouterLink to="/create" class="btn-secondary text-center justify-center sm:justify-start">
              Teslimat Oluştur
            </RouterLink>
          </div>

          <div class="mt-8 flex flex-wrap gap-2.5">
            <div
              v-for="f in features"
              :key="f.label"
              class="flex items-center gap-1.5 rounded-lg border border-stone-200 bg-white px-3 py-1.5 text-xs font-medium text-stone-600 shadow-sm"
            >
              <component :is="f.icon" class="size-3.5 text-orange-500" />
              {{ f.label }}
            </div>
          </div>
        </div>

        <!-- Right — Stats card -->
        <div class="rounded-2xl border border-stone-200 bg-white p-6 shadow-sm">
          <p class="mb-5 text-xs font-semibold uppercase tracking-widest text-stone-400">Platform Özeti</p>
          <div class="space-y-4">
            <div class="flex items-center justify-between rounded-xl bg-orange-50 px-4 py-3.5">
              <span class="text-sm font-medium text-stone-700">Toplam Teslimat</span>
              <span class="text-xl font-bold text-orange-600">1,247</span>
            </div>
            <div class="flex items-center justify-between rounded-xl bg-green-50 px-4 py-3.5">
              <span class="text-sm font-medium text-stone-700">Başarı Oranı</span>
              <span class="text-xl font-bold text-green-600">98.4%</span>
            </div>
            <div class="flex items-center justify-between rounded-xl bg-blue-50 px-4 py-3.5">
              <span class="text-sm font-medium text-stone-700">Aktif Kurye</span>
              <span class="text-xl font-bold text-blue-600">342</span>
            </div>
            <div class="flex items-center justify-between rounded-xl bg-amber-50 px-4 py-3.5">
              <span class="text-sm font-medium text-stone-700">Dağıtılan MON</span>
              <span class="text-xl font-bold text-amber-600">24,680</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>
</template>
