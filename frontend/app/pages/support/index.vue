<script setup lang="ts">
definePageMeta({ requiresAuth: true })

import { ref, onMounted } from 'vue'
import { PhHeadset, PhPlus, PhCaretRight } from '@phosphor-icons/vue'
import { useSupportStore } from '@/stores/useSupportStore'
import { supportApi, type SupportCase } from '@/api/support'
import SupportAccessGate from '@/components/SupportAccessGate.vue'

const support = useSupportStore()
const cases = ref<SupportCase[]>([])
const nextCursor = ref<string | null | undefined>(null)
const loadingMore = ref(false)

const statusLabel: Record<string, string> = {
  open: 'Açık',
  investigating: 'İnceleniyor',
  closed: 'Kapalı',
}

async function load(after?: string) {
  try {
    const result = await supportApi.listCases({ limit: 25, after })
    cases.value = after ? [...cases.value, ...result.data] : result.data
    nextCursor.value = result.nextCursor
    support.markGranted()
  } catch (cause) {
    support.resolveAccessError(cause)
  }
}

async function loadMore() {
  if (!nextCursor.value) return
  loadingMore.value = true
  await load(nextCursor.value)
  loadingMore.value = false
}

onMounted(() => {
  support.markChecking()
  load()
})
</script>

<template>
  <div class="mx-auto max-w-3xl px-5 py-10 sm:px-8">
    <div class="mb-6 flex items-center justify-between">
      <div class="flex items-center gap-2.5">
        <div class="flex size-9 items-center justify-center rounded-lg bg-orange-100">
          <PhHeadset class="size-5 text-orange-600" weight="duotone" />
        </div>
        <h1 class="text-xl font-bold text-stone-900">Destek Konsolu</h1>
      </div>
      <NuxtLink to="/support/new" class="btn-primary"><PhPlus class="size-4" /> Yeni Vaka</NuxtLink>
    </div>

    <SupportAccessGate>
      <div v-if="cases.length === 0" class="card rounded-xl bg-white p-8 text-center text-sm text-stone-500">
        Henüz vaka yok.
      </div>
      <div v-else class="space-y-2">
        <NuxtLink
          v-for="item in cases"
          :key="item.id"
          :to="`/support/${item.id}`"
          class="card flex items-center justify-between rounded-xl bg-white p-4 transition hover:bg-stone-50"
        >
          <div>
            <p class="text-sm font-semibold text-stone-900">Vaka #{{ item.id }} · Teslimat #{{ item.delivery_id }}</p>
            <p class="mt-0.5 text-xs text-stone-500">{{ statusLabel[item.status] || item.status }} · {{ item.assignee || 'Atanmadı' }}</p>
          </div>
          <PhCaretRight class="size-4 text-stone-300" />
        </NuxtLink>
      </div>
      <button v-if="nextCursor" class="btn-secondary mt-4 w-full justify-center" :disabled="loadingMore" @click="loadMore">
        {{ loadingMore ? 'Yükleniyor...' : 'Daha Fazla' }}
      </button>
    </SupportAccessGate>
  </div>
</template>
