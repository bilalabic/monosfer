<script setup lang="ts">
import AppNavbar from '@/components/AppNavbar.vue'
</script>

<template>
  <div class="flex h-screen flex-col overflow-hidden">
    <AppNavbar />
    <main class="map-main min-h-0 flex-1">
      <slot />
    </main>
  </div>
</template>
