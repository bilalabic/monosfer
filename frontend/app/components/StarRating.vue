<script setup lang="ts">
import { computed } from 'vue'

const props = defineProps<{ rating: number; max?: number }>()
const max = computed(() => props.max ?? 5)
const fullStars = computed(() => Math.floor(props.rating))
const hasHalf = computed(() => props.rating % 1 >= 0.5)
const emptyStars = computed(() => max.value - fullStars.value - (hasHalf.value ? 1 : 0))
</script>

<template>
  <span class="inline-flex items-center gap-0.5">
    <svg
      v-for="i in fullStars"
      :key="`full-${i}`"
      class="size-3.5 text-yellow-400"
      viewBox="0 0 20 20"
      fill="currentColor"
    >
      <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
    </svg>
    <svg
      v-if="hasHalf"
      class="size-3.5 text-yellow-400"
      viewBox="0 0 20 20"
      fill="currentColor"
    >
      <defs>
        <linearGradient id="half-grad">
          <stop offset="50%" stop-color="currentColor" />
          <stop offset="50%" stop-color="transparent" />
        </linearGradient>
      </defs>
      <path fill="url(#half-grad)" d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
    </svg>
    <svg
      v-for="i in emptyStars"
      :key="`empty-${i}`"
      class="size-3.5 text-white/20"
      viewBox="0 0 20 20"
      fill="currentColor"
    >
      <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
    </svg>
    <span class="ml-1 text-xs font-medium text-muted-foreground">{{ rating.toFixed(1) }}</span>
  </span>
</template>
