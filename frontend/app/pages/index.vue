<script setup lang="ts">
import HeroSection from '@/components/HeroSection.vue'
import HowItWorksSection from '@/components/HowItWorksSection.vue'
import FeaturesSection from '@/components/FeaturesSection.vue'
import StatsSection from '@/components/StatsSection.vue'
import SecuritySection from '@/components/SecuritySection.vue'
import { PhRocketLaunch, PhCrown, PhCheckCircle, PhPackage, PhBicycle } from '@phosphor-icons/vue'
import { onSpotlightTiltMouseMove, onTiltMouseLeave } from '@/composables/useSpotlight'
</script>

<template>
  <div>
    <HeroSection />
    <StatsSection v-reveal />
    <FeaturesSection v-reveal />
    <how-it-works-section />
    <SecuritySection v-reveal />

    <!-- CTA -->
    <section class="grid-texture relative isolate overflow-hidden px-5 py-20 sm:px-8">
      <div class="aurora-bg" aria-hidden="true">
        <div class="aurora-blob aurora-blob--1" />
        <div class="aurora-blob aurora-blob--2" />
        <div class="aurora-blob aurora-blob--3" />
      </div>

      <!-- Floating props — purely decorative, hidden on small screens to avoid crowding the card -->
      <div class="pointer-events-none absolute inset-0 mx-auto hidden max-w-4xl sm:block" aria-hidden="true">
        <img src="/monad-coin.svg" alt="" class="cta-float-icon absolute left-[6%] top-[20%] size-10 drop-shadow-lg" style="--float-delay: 0s; --float-rot: -8deg">
        <span class="cta-float-icon absolute right-[8%] top-[15%] flex size-12 items-center justify-center rounded-2xl bg-white shadow-lg ring-1 ring-orange-100" style="--float-delay: .9s; --float-rot: 6deg">
          <PhPackage class="size-6 text-orange-500" weight="duotone" />
        </span>
        <img src="/monad-coin.svg" alt="" class="cta-float-icon absolute right-[12%] bottom-[18%] size-7 drop-shadow-lg" style="--float-delay: 1.7s; --float-rot: 10deg">
        <span class="cta-float-icon absolute left-[10%] bottom-[22%] flex size-11 items-center justify-center rounded-2xl bg-white shadow-lg ring-1 ring-orange-100" style="--float-delay: .4s; --float-rot: -6deg">
          <PhBicycle class="size-5 text-orange-500" weight="duotone" />
        </span>
      </div>

      <div class="relative mx-auto max-w-2xl text-center">
        <div
          v-reveal
          class="cta-glow spotlight-card relative overflow-hidden rounded-2xl border border-orange-200 bg-white/80 p-10 shadow-sm backdrop-blur-sm sm:p-14"
          @mousemove="onSpotlightTiltMouseMove"
          @mouseleave="onTiltMouseLeave"
        >
          <div class="tilt-card">
            <p class="mb-3 flex items-center justify-center gap-1.5 text-xs font-semibold uppercase tracking-widest text-orange-500">
              <span class="size-1.5 rounded-full bg-orange-500 animate-pulse-dot" />Hazır mısın?
            </p>
            <h2 class="mb-4 text-3xl font-bold text-stone-900 sm:text-4xl">Hemen Başla</h2>
            <p class="mb-8 leading-relaxed text-stone-500">
              Blockchain güvencesiyle teslimatınızı oluşturun veya kurye olarak teklif verin —
              kurulum yok, saniyeler içinde başlarsınız.
            </p>
            <div class="flex flex-col justify-center gap-3 sm:flex-row">
              <NuxtLink to="/create" class="btn-primary justify-center text-center">
                <PhRocketLaunch class="size-5" weight="duotone" />
                Teslimat Oluştur
              </NuxtLink>
              <NuxtLink to="/couriers" class="btn-secondary justify-center text-center">
                <PhCrown class="size-5 text-orange-500" weight="duotone" />
                Leaderboard'a Bak
              </NuxtLink>
            </div>
            <div class="mt-8 flex flex-wrap items-center justify-center gap-x-6 gap-y-2 border-t border-orange-100 pt-6 text-xs text-stone-500">
              <span class="flex items-center gap-1.5"><PhCheckCircle class="size-4 text-orange-500" weight="fill" />Cüzdanla saniyede bağlan</span>
              <span class="flex items-center gap-1.5"><PhCheckCircle class="size-4 text-orange-500" weight="fill" />Gizli ücret yok</span>
              <span class="flex items-center gap-1.5"><PhCheckCircle class="size-4 text-orange-500" weight="fill" />Her adım zincirde kayıtlı</span>
            </div>
          </div>
        </div>
      </div>
    </section>
  </div>
</template>
