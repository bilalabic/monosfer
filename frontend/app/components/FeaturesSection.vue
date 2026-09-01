<script setup lang="ts">
import { PhVault, PhScales, PhCrown, PhChartLineUp } from '@phosphor-icons/vue'
import { onSpotlightMouseMove } from '@/composables/useSpotlight'

const features = [
  {
    icon: PhVault,
    title: 'Escrow Ödeme',
    desc: 'Para teslimat tamamlanana kadar akıllı sözleşmede kilitli. Hiç kimse tek başına dokunamaz.',
    tag: 'Güvenlik',
  },
  {
    icon: PhChartLineUp,
    title: 'Teklif Sistemi',
    desc: 'Kuryeler fiyatlarını kendileri belirler. Müşteri puan ve fiyatı karşılaştırarak seçer.',
    tag: 'Rekabet',
  },
  {
    icon: PhCrown,
    title: 'Leaderboard',
    desc: 'Her teslimat puanı etkiler. Haftalık en iyiler ödül havuzundan token kazanır.',
    tag: 'Ödüllendirme',
  },
  {
    icon: PhScales,
    title: 'Anlaşmazlık Çözümü',
    desc: 'Uyuşmazlıkta token sahipleri jüri olur, karar blockchain\'e yazılır ve kesindir.',
    tag: 'Adalet',
  },
]
</script>

<template>
  <section class="px-5 py-16 sm:px-8">
    <div class="mx-auto max-w-6xl">
      <div class="mb-10 text-center">
        <p class="mb-2 text-xs font-semibold uppercase tracking-widest text-orange-500">Özellikler</p>
        <h2 class="text-2xl font-bold text-stone-900 sm:text-3xl">Neden Delivera?</h2>
        <p class="mt-2 text-stone-500">Dört katmanlı güvenlik ve şeffaf sistem</p>
      </div>

      <div class="grid gap-5 sm:grid-cols-2">
        <div
          v-for="f in features"
          :key="f.title"
          class="card card-hover spotlight-card rounded-xl bg-white p-6"
          @mousemove="onSpotlightMouseMove"
        >
          <div class="mb-4 flex items-start justify-between">
            <div class="flex size-10 items-center justify-center rounded-xl bg-gradient-to-br from-orange-100 to-amber-50 text-orange-600 ring-1 ring-orange-200/60">
              <component :is="f.icon" class="size-6" weight="duotone" />
            </div>
            <span class="rounded-full border border-orange-200 bg-orange-50 px-2.5 py-0.5 text-xs font-medium text-orange-600">
              {{ f.tag }}
            </span>
          </div>
          <h3 class="mb-1.5 font-semibold text-stone-900">{{ f.title }}</h3>
          <p class="text-sm leading-relaxed text-stone-500">{{ f.desc }}</p>
        </div>
      </div>
    </div>
  </section>
</template>
