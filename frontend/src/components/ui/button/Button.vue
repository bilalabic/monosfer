<script setup lang="ts">
import { computed } from 'vue'
import { cn } from '@/lib/utils'

type ButtonVariant = 'default' | 'secondary' | 'outline' | 'ghost' | 'link' | 'destructive'
type ButtonSize = 'default' | 'sm' | 'lg' | 'icon'

const props = withDefaults(
  defineProps<{
    variant?: ButtonVariant
    size?: ButtonSize
    class?: string
    type?: 'button' | 'submit' | 'reset'
  }>(),
  {
    variant: 'default',
    size: 'default',
    type: 'button',
  },
)

const variantClasses: Record<ButtonVariant, string> = {
  default: 'bg-primary text-primary-foreground shadow-sm hover:bg-primary/90',
  secondary: 'bg-secondary text-secondary-foreground shadow-sm hover:bg-secondary/90',
  outline: 'border border-input bg-background hover:bg-muted hover:text-foreground',
  ghost: 'hover:bg-muted hover:text-foreground',
  link: 'h-auto p-0 text-primary underline-offset-4 hover:underline',
  destructive: 'bg-destructive text-destructive-foreground shadow-sm hover:bg-destructive/90',
}

const sizeClasses: Record<ButtonSize, string> = {
  default: 'h-11 px-5 py-2',
  sm: 'h-9 rounded-md px-3',
  lg: 'h-12 rounded-xl px-8',
  icon: 'h-11 w-11',
}

const buttonClass = computed(() =>
  cn(
    'inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-lg text-sm font-semibold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50',
    variantClasses[props.variant],
    sizeClasses[props.size],
    props.class,
  ),
)
</script>

<template>
  <button :type="type" :class="buttonClass">
    <slot />
  </button>
</template>
