<script setup lang="ts">
import { useSupportStore } from '@/stores/useSupportStore'
import { PhLockKey, PhProhibit, PhWarningCircle } from '@phosphor-icons/vue'

const support = useSupportStore()
</script>

<template>
  <div v-if="support.accessState === 'unknown' || support.accessState === 'checking'" class="flex min-h-[40vh] items-center justify-center">
    <svg class="size-6 animate-spin text-orange-500" fill="none" viewBox="0 0 24 24">
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
    </svg>
  </div>

  <div v-else-if="support.accessState === 'unauthenticated'" class="page-empty mx-auto max-w-lg">
    <PhLockKey class="mx-auto mb-3 size-10 text-stone-300" weight="duotone" />
    <h2 class="font-semibold text-stone-900">Giriş gerekli</h2>
    <p class="mt-1 text-sm text-stone-500">Destek konsoluna erişmek için cüzdanınızla giriş yapın.</p>
    <NuxtLink to="/login" class="btn-primary mt-4 inline-flex">Giriş Yap</NuxtLink>
  </div>

  <div v-else-if="support.accessState === 'denied'" class="page-empty mx-auto max-w-lg">
    <PhProhibit class="mx-auto mb-3 size-10 text-stone-300" weight="duotone" />
    <h2 class="font-semibold text-stone-900">Erişim yok</h2>
    <p class="mt-1 text-sm text-stone-500">Bu cüzdanın destek konsolu erişimi yok.</p>
  </div>

  <div v-else-if="support.accessState === 'disabled'" class="page-empty mx-auto max-w-lg">
    <PhWarningCircle class="mx-auto mb-3 size-10 text-stone-300" weight="duotone" />
    <h2 class="font-semibold text-stone-900">Destek modülü kapalı</h2>
    <p class="mt-1 text-sm text-stone-500">Bu ortamda destek/operasyon modülü etkin değil.</p>
  </div>

  <slot v-else />
</template>
