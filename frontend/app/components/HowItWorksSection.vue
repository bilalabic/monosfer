<script setup lang="ts">
import { PhPackage as Package, PhUsers as Users, PhCheckCircle as CheckCircle2, PhStar as Star, PhLightning as Zap, PhSealCheck as BadgeCheck } from '@phosphor-icons/vue'

const steps = [
  {
    num: '1',
    icon: Package,
    title: 'Teslimat Talebi',
    desc: 'Müşteri oluşturur ve ödemeyi akıllı sözleşmeye kilitler.',
  },
  {
    num: '2',
    icon: Users,
    title: 'Kuryeler Teklif Verir',
    desc: 'Kaç token istediğini yazarlar. Her teklif teminatlıdır.',
  },
  {
    num: '3',
    icon: Star,
    title: 'Müşteri Seçer',
    desc: 'Puan ve fiyata göre en uygun kuryeyi seçer.',
  },
  {
    num: '4',
    icon: Zap,
    title: 'Teslimat Gerçekleşir',
    desc: 'İki tarafın onayıyla teslim blockchain\'e yazılır.',
  },
  {
    num: '5',
    icon: CheckCircle2,
    title: 'Otomatik Ödeme',
    desc: 'Akıllı sözleşme ödemeyi kuryeye anında aktarır.',
  },
  {
    num: '6',
    icon: BadgeCheck,
    title: 'Puan & Leaderboard',
    desc: 'Müşteri puanlar, leaderboard otomatik güncellenir.',
  },
]
</script>

<template>
  <section class="px-5 py-16 sm:px-8 bg-stone-50">
    <div class="mx-auto max-w-6xl">
      <div class="mb-10 text-center">
        <p class="mb-2 text-xs font-semibold uppercase tracking-widest text-orange-500">Nasıl Çalışır?</p>
        <h2 class="text-2xl font-bold text-stone-900 sm:text-3xl">6 adımda güvenli teslimat</h2>
      </div>

      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <div
          v-for="step in steps"
          :key="step.num"
          class="card card-hover rounded-xl bg-white p-5"
        >
          <div class="mb-3 flex items-center gap-3">
            <div class="flex size-9 items-center justify-center rounded-lg bg-orange-100 text-orange-600">
              <component :is="step.icon" class="size-5" weight="duotone" />
            </div>
            <span class="text-xs font-bold text-stone-400">Adım {{ step.num }}</span>
          </div>
          <h3 class="mb-1 text-sm font-semibold text-stone-900">{{ step.title }}</h3>
          <p class="text-xs leading-relaxed text-stone-500">{{ step.desc }}</p>
        </div>
      </div>
    </div>
  </section>
</template>
