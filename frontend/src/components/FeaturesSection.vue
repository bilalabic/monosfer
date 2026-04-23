<script setup lang="ts">
import { Lock, Gavel, Trophy, TrendingUp } from 'lucide-vue-next'

const features = [
  {
    icon: Lock,
    title: 'Escrow Ödeme',
    desc: 'Para teslimat tamamlanana kadar akıllı sözleşmede kilitli. Hiç kimse tek başına dokunamaz.',
    tag: 'Güvenlik',
    iconClass: 'bg-orange-100 text-orange-600',
    tagClass: 'bg-orange-50 text-orange-600 border-orange-200',
  },
  {
    icon: TrendingUp,
    title: 'Teklif Sistemi',
    desc: 'Kuryeler fiyatlarını kendileri belirler. Müşteri puan ve fiyatı karşılaştırarak seçer.',
    tag: 'Rekabet',
    iconClass: 'bg-blue-100 text-blue-600',
    tagClass: 'bg-blue-50 text-blue-600 border-blue-200',
  },
  {
    icon: Trophy,
    title: 'Leaderboard',
    desc: 'Her teslimat puanı etkiler. Haftalık en iyiler ödül havuzundan token kazanır.',
    tag: 'Ödüllendirme',
    iconClass: 'bg-amber-100 text-amber-600',
    tagClass: 'bg-amber-50 text-amber-600 border-amber-200',
  },
  {
    icon: Gavel,
    title: 'Anlaşmazlık Çözümü',
    desc: 'Uyuşmazlıkta token sahipleri jüri olur, karar blockchain\'e yazılır ve kesindir.',
    tag: 'Adalet',
    iconClass: 'bg-green-100 text-green-600',
    tagClass: 'bg-green-50 text-green-600 border-green-200',
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
          class="card card-hover rounded-xl bg-white p-6"
        >
          <div class="mb-4 flex items-start justify-between">
            <div :class="['flex size-10 items-center justify-center rounded-lg', f.iconClass]">
              <component :is="f.icon" class="size-5" />
            </div>
            <span :class="['rounded-full border px-2.5 py-0.5 text-xs font-medium', f.tagClass]">
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
