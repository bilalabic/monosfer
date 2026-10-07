<script setup lang="ts">
import AppNavbar from '@/components/AppNavbar.vue'
import AppFooter from '@/components/AppFooter.vue'
const localTesting = Number(useRuntimeConfig().public.chainId) === 31337
const route = useRoute()
</script>

<template>
  <div class="min-h-screen flex flex-col">
    <AppNavbar />
    <div v-if="localTesting" class="border-b border-amber-200 bg-amber-50 px-5 py-2 text-center text-xs text-amber-900">
      Yerel test ortamı · Örnek kurye ve ilanlar · İşlemler yerel zincirde, test MON ile yapılır
    </div>
    <main class="flex-1" :class="{ 'application-main': route.path !== '/' }">
      <slot />
    </main>
    <AppFooter />
  </div>
</template>
