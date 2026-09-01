<script setup lang="ts">
import HeroSection from '@/components/HeroSection.vue'
import HowItWorksSection from '@/components/HowItWorksSection.vue'
import FeaturesSection from '@/components/FeaturesSection.vue'
import StatsSection from '@/components/StatsSection.vue'
import SecuritySection from '@/components/SecuritySection.vue'
import { PhRocketLaunch, PhTrophy } from '@phosphor-icons/vue'
</script>

<template>
  <div>
    <HeroSection />
    <StatsSection v-reveal />
    <FeaturesSection v-reveal />
    <HowItWorksSection v-reveal />
    <SecuritySection v-reveal />

    <!-- CTA -->
    <section class="px-5 py-16 sm:px-8">
      <div class="mx-auto max-w-2xl text-center">
        <div v-reveal class="rounded-2xl border border-orange-200 bg-orange-50 p-10">
          <h2 class="mb-3 text-2xl font-bold text-stone-900">Hemen Başla</h2>
          <p class="mb-7 text-stone-500">Blockchain güvencesiyle teslimatınızı oluşturun veya kurye olarak teklif verin.</p>
          <div class="flex flex-col justify-center gap-3 sm:flex-row">
            <NuxtLink to="/create" class="btn-primary justify-center text-center">
              <PhRocketLaunch class="size-5" weight="duotone" />
              Teslimat Oluştur
            </NuxtLink>
            <NuxtLink to="/couriers" class="btn-secondary justify-center text-center">
              <PhTrophy class="size-5 text-orange-500" weight="duotone" />
              Leaderboard'a Bak
            </NuxtLink>
          </div>
        </div>
      </div>
    </section>
  </div>
</template>
