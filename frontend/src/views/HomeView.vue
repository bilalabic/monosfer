<script setup lang="ts">
import HeroSection from '@/components/HeroSection.vue'
import HowItWorksSection from '@/components/HowItWorksSection.vue'
import FeaturesSection from '@/components/FeaturesSection.vue'
import StatsSection from '@/components/StatsSection.vue'
import SecuritySection from '@/components/SecuritySection.vue'
import { RouterLink } from 'vue-router'
import { PhRocketLaunch, PhTrophy } from '@phosphor-icons/vue'
</script>

<template>
  <div>
    <HeroSection />
    <StatsSection v-motion-slide-visible-bottom :duration="500" />
    <FeaturesSection v-motion-slide-visible-bottom :duration="500" />
    <HowItWorksSection v-motion-slide-visible-bottom :duration="500" />
    <SecuritySection v-motion-slide-visible-bottom :duration="500" />

    <!-- CTA -->
    <section class="px-5 py-16 sm:px-8">
      <div class="mx-auto max-w-2xl text-center">
        <div v-motion-slide-visible-bottom :duration="500" class="rounded-2xl border border-orange-200 bg-orange-50 p-10">
          <h2 class="mb-3 text-2xl font-bold text-stone-900">Hemen Başla</h2>
          <p class="mb-7 text-stone-500">Blockchain güvencesiyle teslimatınızı oluşturun veya kurye olarak teklif verin.</p>
          <div class="flex flex-col justify-center gap-3 sm:flex-row">
            <RouterLink to="/create" class="btn-primary justify-center text-center">
              <PhRocketLaunch class="size-5" weight="duotone" />
              Teslimat Oluştur
            </RouterLink>
            <RouterLink to="/couriers" class="btn-secondary justify-center text-center">
              <PhTrophy class="size-5 text-orange-500" weight="duotone" />
              Leaderboard'a Bak
            </RouterLink>
          </div>
        </div>
      </div>
    </section>
  </div>
</template>
