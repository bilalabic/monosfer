<script setup lang="ts">
withDefaults(defineProps<{ amount: number; size?: 'sm' | 'md' | 'lg'; symbol?: string }>(), {
  symbol: 'DLV',
})
</script>

<template>
  <span
    :class="[
      'inline-flex items-center gap-1 font-semibold tabular-nums',
      size === 'sm' ? 'text-xs' : size === 'lg' ? 'text-xl' : 'text-sm',
    ]"
  >
    <span
      :class="[
        'inline-flex items-center justify-center rounded-full bg-orange-500 font-bold text-white leading-none',
        size === 'sm' ? 'size-3.5 text-[8px]' : size === 'lg' ? 'size-6 text-xs' : 'size-4 text-[9px]',
      ]"
    >
      M
    </span>
    <span class="text-stone-900">{{ amount }}</span>
    <span class="font-normal text-stone-400" :class="size === 'sm' ? 'text-[10px]' : 'text-xs'">{{ symbol }}</span>
  </span>
</template>
