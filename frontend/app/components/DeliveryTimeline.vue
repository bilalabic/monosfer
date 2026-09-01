<script setup lang="ts">
import type { Component } from 'vue'
import { PhCheckCircle as CheckCircle2, PhPackage as Package, PhUser as User, PhTruck as Truck, PhFlag as Flag } from '@phosphor-icons/vue'

interface Step { step: string; label: string; completed: boolean; time?: string }
defineProps<{ timeline: Step[] }>()

const icons: Record<string, Component> = { created: Package, accepted: User, pickup: Truck, transit: Truck, delivered: Flag }
</script>

<template>
  <div>
    <div v-for="(item, index) in timeline" :key="item.step" class="flex items-start gap-3">
      <div class="flex flex-col items-center">
        <div
          :class="[
            'flex size-7 items-center justify-center rounded-full border-2 transition-all',
            item.completed
              ? 'border-green-400 bg-green-400 text-white'
              : 'border-stone-200 bg-white text-stone-400',
          ]"
        >
          <CheckCircle2 v-if="item.completed" class="size-3.5" weight="fill" />
          <component v-else :is="icons[item.step] || Package" class="size-3" weight="bold" />
        </div>
        <div v-if="index < timeline.length - 1" :class="['mt-1 mb-1 w-0.5 h-7', item.completed ? 'bg-green-300' : 'bg-stone-200']" />
      </div>
      <div class="flex-1 pb-5">
        <div class="flex items-center justify-between">
          <span :class="['text-sm font-medium', item.completed ? 'text-stone-900' : 'text-stone-400']">{{ item.label }}</span>
          <span v-if="item.time" class="text-xs text-stone-400">{{ item.time }}</span>
          <span v-else-if="!item.completed" class="text-xs text-stone-300">Bekliyor</span>
        </div>
      </div>
    </div>
  </div>
</template>
