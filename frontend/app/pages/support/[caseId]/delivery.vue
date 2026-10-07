<script setup lang="ts">
definePageMeta({ requiresAuth: true })

import { ref, onMounted } from 'vue'
import { PhArrowLeft } from '@phosphor-icons/vue'
import { useSupportStore } from '@/stores/useSupportStore'
import { supportApi, type SupportCaseDetail, type SupportEvidenceMeta } from '@/api/support'
import SupportAccessGate from '@/components/SupportAccessGate.vue'

const route = useRoute()
const router = useRouter()
const support = useSupportStore()
const caseId = route.params.caseId as string

const summary = ref<Record<string, unknown> | null>(null)
const privateData = ref<Record<string, unknown> | null>(null)
const privateError = ref('')
const evidence = ref<SupportEvidenceMeta[]>([])
const evidenceContent = ref<Record<string, Record<string, unknown>>>({})
const openEvidenceId = ref('')

let deliveryId = ''

async function viewEvidence(item: SupportEvidenceMeta) {
  if (evidenceContent.value[item.id]) {
    openEvidenceId.value = openEvidenceId.value === item.id ? '' : item.id
    return
  }
  try {
    evidenceContent.value[item.id] = await supportApi.getDeliveryEvidenceContent(deliveryId, item.id)
    openEvidenceId.value = item.id
  } catch {
    // Not-ready/unavailable content — leave the row collapsed.
  }
}

async function load() {
  try {
    const detail: SupportCaseDetail = await supportApi.getCase(caseId)
    deliveryId = detail.delivery_id
    summary.value = await supportApi.getDelivery(deliveryId)
    evidence.value = (await supportApi.getDeliveryEvidence(deliveryId)).data
    try {
      privateData.value = await supportApi.getDeliveryPrivate(deliveryId)
    } catch (cause) {
      privateError.value = cause instanceof Error ? cause.message : 'Private veri bu vaka için açık değil'
    }
    support.markGranted()
  } catch (cause) {
    support.resolveAccessError(cause)
  }
}

onMounted(() => {
  support.markChecking()
  load()
})
</script>

<template>
  <div class="page-shell page-shell--form">
    <button class="mb-6 flex items-center gap-1.5 text-sm text-stone-500 hover:text-stone-900" @click="router.back()">
      <PhArrowLeft class="size-4" weight="bold" /> Vakaya Dön
    </button>

    <page-header compact eyebrow="Destek süreci" title="Teslimat incelemesi" description="Vakaya ait teslimat bilgileri ve kanıtlar." />
    <SupportAccessGate>
      <div class="space-y-5">
        <div v-if="summary" class="card rounded-xl bg-white p-5">
          <p class="mb-3 text-xs font-semibold uppercase tracking-wide text-stone-400">Teslimat Özeti</p>
          <dl class="grid grid-cols-1 gap-1.5 text-sm">
            <div v-for="(value, key) in summary" :key="key" class="flex justify-between gap-3 border-b border-stone-50 py-1">
              <dt class="text-stone-400">{{ key }}</dt>
              <dd class="max-w-[60%] truncate text-right font-mono text-xs text-stone-700">{{ String(value) }}</dd>
            </div>
          </dl>
        </div>

        <div class="card rounded-xl bg-white p-5">
          <p class="mb-3 text-xs font-semibold uppercase tracking-wide text-stone-400">Private Veri</p>
          <dl v-if="privateData" class="grid grid-cols-1 gap-1.5 text-sm">
            <div v-for="(value, key) in privateData" :key="key" class="flex justify-between gap-3 border-b border-stone-50 py-1">
              <dt class="text-stone-400">{{ key }}</dt>
              <dd class="max-w-[60%] truncate text-right font-mono text-xs text-stone-700">{{ String(value) }}</dd>
            </div>
          </dl>
          <p v-else class="text-sm text-stone-500">{{ privateError || 'Yükleniyor...' }}</p>
        </div>

        <div class="card rounded-xl bg-white p-5">
          <p class="mb-3 text-xs font-semibold uppercase tracking-wide text-stone-400">Kanıtlar ({{ evidence.length }})</p>
          <div v-if="evidence.length === 0" class="text-sm text-stone-400">Kanıt yok.</div>
          <div v-else class="space-y-2">
            <div v-for="item in evidence" :key="item.id" class="rounded-lg border border-stone-100 bg-stone-50 p-2.5 text-xs">
              <button type="button" class="flex w-full items-center justify-between text-left" @click="viewEvidence(item)">
                <span>{{ item.content_type }} · {{ item.status }}</span>
                <span class="text-stone-400">{{ new Date(item.created_at).toLocaleString('tr-TR') }}</span>
              </button>
              <pre
                v-if="openEvidenceId === item.id && evidenceContent[item.id]"
                class="mt-1.5 overflow-x-auto whitespace-pre-wrap text-stone-700"
              >{{ JSON.stringify(evidenceContent[item.id], null, 2) }}</pre>
            </div>
          </div>
        </div>
      </div>
    </SupportAccessGate>
  </div>
</template>
