<script setup lang="ts">
definePageMeta({ requiresAuth: true })

import { ref, onMounted } from 'vue'
import { PhArrowLeft, PhCircleNotch, PhFileText } from '@phosphor-icons/vue'
import { useSupportStore } from '@/stores/useSupportStore'
import { supportApi, type SupportCaseDetail, type SupportCaseStatus } from '@/api/support'
import SupportAccessGate from '@/components/SupportAccessGate.vue'

const route = useRoute()
const router = useRouter()
const support = useSupportStore()
const caseId = route.params.caseId as string

const detail = ref<SupportCaseDetail | null>(null)
const status = ref<SupportCaseStatus>('open')
const assignee = ref('')
const note = ref('')
const saving = ref(false)
const error = ref('')
const message = ref('')

async function load() {
  try {
    detail.value = await supportApi.getCase(caseId)
    status.value = detail.value.status
    assignee.value = detail.value.assignee || ''
    support.markGranted()
  } catch (cause) {
    support.resolveAccessError(cause)
  }
}

async function save() {
  saving.value = true
  error.value = ''
  message.value = ''
  try {
    const updated = await supportApi.updateCase(caseId, {
      status: status.value,
      assignee: assignee.value.trim() || null,
      note: note.value.trim() || undefined,
    })
    detail.value = { ...updated, events: detail.value?.events ?? [] }
    note.value = ''
    message.value = 'Vaka güncellendi.'
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : 'Vaka güncellenemedi'
  } finally {
    saving.value = false
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
      <PhArrowLeft class="size-4" weight="bold" /> Geri
    </button>

    <SupportAccessGate>
      <div v-if="detail" class="space-y-5">
        <page-header compact eyebrow="Destek süreci" :title="`Vaka #${detail.id}`" :description="`Teslimat #${detail.delivery_id}`">
          <nuxt-link :to="`/support/${caseId}/delivery`" class="btn-secondary text-sm">
            <PhFileText class="size-4" /> Teslimat Detayı
          </nuxt-link>
        </page-header>
        <p class="break-all text-sm text-stone-500">Oluşturan: {{ detail.created_by }}</p>

        <form class="card space-y-4 rounded-xl bg-white p-5" @submit.prevent="save">
          <div>
            <label class="mb-1.5 block text-sm font-medium text-stone-700">Durum</label>
            <select v-model="status" class="input">
              <option value="open">Açık</option>
              <option value="investigating">İnceleniyor</option>
              <option value="closed">Kapalı</option>
            </select>
          </div>
          <div>
            <label class="mb-1.5 block text-sm font-medium text-stone-700">Atanan cüzdan</label>
            <input v-model.trim="assignee" type="text" class="input font-mono text-sm" placeholder="0x..." />
          </div>
          <div>
            <label class="mb-1.5 block text-sm font-medium text-stone-700">Yeni not</label>
            <textarea v-model="note" rows="3" maxlength="2000" class="input resize-none" />
          </div>
          <button type="submit" class="btn-primary w-full justify-center" :disabled="saving">
            <PhCircleNotch v-if="saving" class="size-4 animate-spin" />
            {{ saving ? 'Kaydediliyor...' : 'Kaydet' }}
          </button>
          <p v-if="message" class="text-sm text-green-600">{{ message }}</p>
          <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
        </form>

        <p class="text-xs text-stone-400">{{ detail.events.length }} olay kaydı.</p>
      </div>
    </SupportAccessGate>
  </div>
</template>
