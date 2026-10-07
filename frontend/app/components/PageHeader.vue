<script setup lang="ts">
withDefaults(defineProps<{
  eyebrow?: string
  title: string
  description?: string
  compact?: boolean
  centered?: boolean
}>(), { eyebrow: 'Delivera', description: '', compact: false, centered: false })
</script>

<template>
  <header :class="['page-header', { 'page-header--compact': compact, 'page-header--centered': centered }]">
    <div class="page-header__copy">
      <p class="page-eyebrow"><span aria-hidden="true" />{{ eyebrow }}</p>
      <h1>{{ title }}</h1>
      <p v-if="description" class="page-header__description">{{ description }}</p>
      <div v-if="$slots.meta" class="page-header__meta"><slot name="meta" /></div>
    </div>
    <div v-if="$slots.default" class="page-header__aside"><slot /></div>
  </header>
</template>
