<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { PhArrowRight as ArrowRight, PhVault, PhCircuitry, PhShieldCheck } from '@phosphor-icons/vue'
import { onSpotlightMouseMove, onTiltMouseMove, onTiltMouseLeave } from '@/composables/useSpotlight'

function onCardMouseMove(e: MouseEvent) {
  onSpotlightMouseMove(e)
  onTiltMouseMove(e)
}

const features = [
  { icon: PhVault, label: 'Escrow Güvenceli' },
  { icon: PhCircuitry, label: 'Monad Blockchain' },
  { icon: PhShieldCheck, label: 'Finalized Doğrulama' },
]

const stats = [
  { label: 'Ağ', value: 'Monad' },
  { label: 'Veri Durumu', value: 'Finalized' },
  { label: 'Oturum', value: 'SIWE' },
  { label: 'Teslim Kanıtı', value: 'OTP + EIP-712' },
]

// Route marker animation is purely decorative — skip it under prefers-reduced-motion.
const routePath = 'M20,150 C120,20 260,180 380,40'
const reduceMotion = ref(false)
onMounted(() => {
  reduceMotion.value = window.matchMedia('(prefers-reduced-motion: reduce)').matches
})
</script>

<template>
  <section class="home-hero grid-texture relative isolate overflow-hidden px-5 pb-20 sm:px-8">
    <div class="aurora-bg" aria-hidden="true">
      <div class="aurora-blob aurora-blob--1" />
      <div class="aurora-blob aurora-blob--2" />
      <div class="aurora-blob aurora-blob--3" />
    </div>
    <div class="mx-auto max-w-6xl">
      <!-- Badge -->
      <div
        v-reveal
        class="mb-6 inline-flex items-center gap-2 rounded-full border border-orange-200 bg-orange-50 px-3.5 py-1.5 text-xs font-medium text-orange-700"
      >
        <span class="size-1.5 rounded-full bg-orange-500 animate-pulse-dot" />
        Monad Hackathon 2026 · Merkeziyetsiz Teslimat
      </div>

      <div class="grid gap-12 lg:grid-cols-2 lg:items-center">
        <!-- Left -->
        <div>
          <h1
            v-reveal="{ delay: 100 }"
            class="font-heading mb-5 text-4xl font-bold leading-[0.95] tracking-tighter text-stone-900 sm:text-6xl lg:text-7xl"
          >
            Teslimatı güvenli,<br />
            <span class="text-mark">ücretlendirmeyi</span> <span class="text-mark text-mark--2">adil</span><br />
            hale getiriyoruz.
          </h1>
          <p
            v-reveal="{ delay: 200 }"
            class="mb-8 text-base leading-relaxed text-stone-500"
          >
            Kuryeler kendi fiyatlarını belirler, müşteriler puana göre seçer.
            Ödeme akıllı sözleşmede kilitli — teslim edilene kadar hiç kimse dokunamaz.
          </p>
          <div
            v-reveal="{ delay: 300 }"
            class="flex flex-col gap-3 sm:flex-row"
          >
            <NuxtLink to="/deliveries" class="btn-primary text-center justify-center sm:justify-start">
              Teslimatları Gör
              <ArrowRight class="size-4" weight="bold" />
            </NuxtLink>
            <NuxtLink to="/create" class="btn-secondary text-center justify-center sm:justify-start">
              Teslimat Oluştur
            </NuxtLink>
          </div>

          <div class="mt-8 flex flex-wrap gap-2.5">
            <div
              v-for="f in features"
              :key="f.label"
              class="flex items-center gap-1.5 rounded-lg border border-stone-200 bg-white px-3 py-1.5 text-xs font-medium text-stone-600 shadow-sm"
            >
              <component :is="f.icon" class="size-4 text-orange-500" weight="duotone" />
              {{ f.label }}
            </div>
          </div>
        </div>

        <!-- Right — Live route visual + stats -->
        <div
          v-reveal="{ delay: 200 }"
          class="spotlight-card rounded-2xl border border-stone-200 bg-white shadow-sm transition-shadow duration-300 hover:shadow-lg"
          @mousemove="onCardMouseMove"
          @mouseleave="onTiltMouseLeave"
        >
          <div class="tilt-card p-6">
            <div class="mb-4 flex items-center gap-2">
              <span class="size-1.5 rounded-full bg-orange-500 animate-pulse-dot" />
              <p class="text-xs font-semibold uppercase tracking-widest text-stone-400">Zincir Üstü Teslimat Akışı</p>
            </div>

            <!-- Route mockup -->
            <svg viewBox="0 0 400 200" class="h-40 w-full sm:h-44" aria-hidden="true">
              <path
                :d="routePath"
                fill="none"
                stroke-width="3"
                stroke-linecap="round"
                stroke-dasharray="2 10"
                class="stroke-orange-300"
              />
              <!-- lit-up trail chasing the courier marker -->
              <path
                v-if="!reduceMotion"
                :d="routePath"
                pathLength="100"
                fill="none"
                stroke-width="3"
                stroke-linecap="round"
                class="route-trail stroke-orange-500"
              />
              <!-- origin -->
              <circle cx="20" cy="150" r="6" class="fill-stone-400" />
              <text x="20" y="172" text-anchor="middle" class="fill-stone-500 text-[10px] font-medium">Depo</text>
              <!-- destination -->
              <circle cx="380" cy="40" r="9" class="fill-orange-500/20">
                <animate attributeName="r" values="9;14;9" dur="2s" repeatCount="indefinite" />
                <animate attributeName="opacity" values="0.6;0;0.6" dur="2s" repeatCount="indefinite" />
              </circle>
              <circle cx="380" cy="40" r="6" class="fill-orange-500" />
              <text x="380" y="24" text-anchor="middle" class="fill-orange-600 text-[10px] font-medium">Teslim Noktası</text>
              <!-- moving courier (parked at the origin when motion is reduced) -->
              <g :transform="reduceMotion ? 'translate(20,150)' : undefined">
                <circle r="10" class="fill-orange-500/25">
                  <animate attributeName="r" values="9;15;9" dur="1.4s" repeatCount="indefinite" />
                  <animate attributeName="opacity" values="0.5;0;0.5" dur="1.4s" repeatCount="indefinite" />
                </circle>
                <circle r="8" class="fill-stone-900" />
                <circle r="8" fill="none" stroke-width="1.5" class="stroke-white/70" />
                <polygon points="-2,-3.5 4,0 -2,3.5" class="fill-white" />
                <animateMotion v-if="!reduceMotion" :path="routePath" dur="4s" repeatCount="indefinite" rotate="auto" />
              </g>
            </svg>

            <div class="mt-2 grid grid-cols-2 gap-3">
              <div v-for="s in stats" :key="s.label" class="rounded-xl bg-orange-50 px-3.5 py-3">
                <p class="text-[11px] font-medium text-stone-500">{{ s.label }}</p>
                <p class="text-lg font-bold text-orange-600">{{ s.value }}</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>
</template>
