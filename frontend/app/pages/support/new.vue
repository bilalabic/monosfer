<script setup lang="ts">
definePageMeta({ requiresAuth: true })

import { ref, onMounted } from 'vue'
import { PhArrowLeft, PhCircleNotch } from '@phosphor-icons/vue'
import { useSupportStore } from '@/stores/useSupportStore'
import { supportApi } from '@/api/support'
import SupportAccessGate from '@/components/SupportAccessGate.vue'

const router = useRouter()
const support = useSupportStore()

const deliveryId = ref('')
const assignee = ref('')
const note = ref('')
const saving = ref(false)
const error = ref('')

async function checkAccess() {
  try {
    await supportApi.listCases({ limit: 1 })
    support.markGranted()
  } catch (cause) {
    support.resolveAccessError(cause)
  }
}

async function submit() {
  if (!deliveryId.value.trim()) return
  saving.value = true
  error.value = ''
  try {
    const created = await supportApi.createCase({
      id: deliveryId.value.trim(),
      assignee: assignee.value.trim() || undefined,
      note: note.value.trim() || undefined,
    })
    router.push(`/support/${created.id}`)
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : 'Vaka oluşturulamadı'
  } finally {
    saving.value = false
  }
}

onMounted(() => {
  support.markChecking()
  checkAccess()
})
</script>

<template>
  <div class="mx-auto max-w-lg px-5 py-10 sm:px-8">
    <button class="mb-6 flex items-center gap-1.5 text-sm text-stone-500 hover:text-stone-900" @click="router.back()">
      <PhArrowLeft class="size-4" weight="bold" /> Geri
    </button>
    <h1 class="mb-5 text-xl font-bold text-stone-900">Yeni Destek Vakası</h1>

    <SupportAccessGate>
      <form class="card space-y-4 rounded-xl bg-white p-5" @submit.prevent="submit">
        <div>
          <label class="mb-1.5 block text-sm font-medium text-stone-700">Teslimat ID</label>
          <input v-model.trim="deliveryId" type="text" class="input" placeholder="Örn: 42" required />
        </div>
        <div>
          <label class="mb-1.5 block text-sm font-medium text-stone-700">Atanacak cüzdan (opsiyonel)</label>
          <input v-model.trim="assignee" type="text" class="input font-mono text-sm" placeholder="0x..." />
        </div>
        <div>
          <label class="mb-1.5 block text-sm font-medium text-stone-700">Not (opsiyonel)</label>
          <textarea v-model="note" rows="3" maxlength="2000" class="input resize-none" />
        </div>
        <button type="submit" class="btn-primary w-full justify-center" :disabled="saving || !deliveryId.trim()">
          <PhCircleNotch v-if="saving" class="size-4 animate-spin" />
          {{ saving ? 'Oluşturuluyor...' : 'Vaka Oluştur' }}
        </button>
        <p v-if="error" class="text-sm text-red-600">{{ error }}</p>
      </form>
    </SupportAccessGate>
  </div>
</template>
