<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { PhCamera, PhCircleNotch, PhFileText, PhPaperPlaneTilt } from '@phosphor-icons/vue'
import { evidenceApi, EVIDENCE_TEXT_MAX_BYTES, EVIDENCE_IMAGE_MAX_BYTES, type EvidenceMeta } from '@/api/evidence'
import type { ChainDeliveryState } from '@/api/deliveries'

const props = defineProps<{ deliveryId: string; chainState: ChainDeliveryState }>()

// Matches the backend's tracking/evidence access window.
const ACTIVE_STATES: ChainDeliveryState[] = ['ReadyForPickup', 'InTransit']
const active = computed(() => ACTIVE_STATES.includes(props.chainState))

const items = ref<EvidenceMeta[]>([])
const loading = ref(false)
const uploading = ref(false)
const error = ref('')
const noteText = ref('')
const viewingId = ref('')
const viewedContent = ref<Record<string, string>>({})

async function load() {
  if (!active.value) return
  loading.value = true
  try {
    items.value = await evidenceApi.list(props.deliveryId)
  } catch {
    // Evidence list is a supplementary view — a failed fetch shouldn't block the rest of the page.
  } finally {
    loading.value = false
  }
}

onMounted(load)

function textByteLength(text: string) {
  return new TextEncoder().encode(text).length
}

function decodedBase64Length(base64: string) {
  const padding = base64.endsWith('==') ? 2 : base64.endsWith('=') ? 1 : 0
  return Math.floor((base64.length * 3) / 4) - padding
}

function fileToBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => {
      const result = reader.result as string
      resolve(result.slice(result.indexOf(',') + 1))
    }
    reader.onerror = () => reject(new Error('Dosya okunamadı'))
    reader.readAsDataURL(file)
  })
}

async function submitNote() {
  if (!noteText.value.trim()) return
  if (textByteLength(noteText.value) > EVIDENCE_TEXT_MAX_BYTES) {
    error.value = `Not en fazla ${EVIDENCE_TEXT_MAX_BYTES} byte olabilir.`
    return
  }
  uploading.value = true
  error.value = ''
  try {
    await evidenceApi.upload(props.deliveryId, { contentType: 'text/plain', text: noteText.value.trim() })
    noteText.value = ''
    await load()
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : 'Kanıt yüklenemedi'
  } finally {
    uploading.value = false
  }
}

async function submitPhoto(event: Event) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) return
  if (file.type !== 'image/png' && file.type !== 'image/jpeg') {
    error.value = 'Yalnız PNG veya JPEG desteklenir.'
    input.value = ''
    return
  }
  uploading.value = true
  error.value = ''
  try {
    const contentBase64 = await fileToBase64(file)
    if (decodedBase64Length(contentBase64) > EVIDENCE_IMAGE_MAX_BYTES) {
      error.value = `Fotoğraf en fazla ${EVIDENCE_IMAGE_MAX_BYTES} byte olabilir (çözülmüş boyut).`
      return
    }
    await evidenceApi.upload(props.deliveryId, { contentType: file.type, contentBase64 })
    await load()
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : 'Fotoğraf yüklenemedi'
  } finally {
    uploading.value = false
    input.value = ''
  }
}

async function viewContent(item: EvidenceMeta) {
  if (viewedContent.value[item.evidenceId]) {
    viewingId.value = viewingId.value === item.evidenceId ? '' : item.evidenceId
    return
  }
  error.value = ''
  try {
    const content = await evidenceApi.content(props.deliveryId, item.evidenceId)
    viewedContent.value[item.evidenceId] = content.text ?? '[fotoğraf içeriği]'
    viewingId.value = item.evidenceId
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : 'Bu kanıtı görüntüleme yetkiniz yok'
  }
}
</script>

<template>
  <div v-if="active" class="card space-y-4 rounded-xl bg-white p-5">
    <p class="text-xs font-semibold uppercase tracking-wide text-stone-400">Teslimat Kanıtı</p>

    <div class="space-y-2">
      <textarea
        v-model="noteText"
        rows="2"
        maxlength="2000"
        class="input resize-none"
        placeholder="Kısa not ekleyin (ör. teslim koşulu, gecikme nedeni)"
      />
      <div class="flex gap-2">
        <button class="btn-secondary flex-1 justify-center" :disabled="uploading || !noteText.trim()" @click="submitNote">
          <PhCircleNotch v-if="uploading" class="size-4 animate-spin" />
          <PhPaperPlaneTilt v-else class="size-4" /> Not Ekle
        </button>
        <label class="btn-secondary flex-1 cursor-pointer justify-center">
          <PhCamera class="size-4" /> Fotoğraf Ekle
          <input type="file" accept="image/png,image/jpeg" class="hidden" :disabled="uploading" @change="submitPhoto" />
        </label>
      </div>
      <p v-if="error" class="text-xs text-red-600">{{ error }}</p>
    </div>

    <div v-if="items.length > 0" class="space-y-2 border-t border-stone-100 pt-3">
      <div v-for="item in items" :key="item.evidenceId" class="rounded-lg border border-stone-100 bg-stone-50 p-2.5 text-xs">
        <button type="button" class="flex w-full items-center justify-between gap-2 text-left" @click="viewContent(item)">
          <span class="flex items-center gap-1.5 text-stone-600">
            <PhFileText class="size-3.5" /> {{ item.contentType }} · {{ item.status }}
          </span>
          <span class="text-stone-400">{{ new Date(item.createdAt).toLocaleString('tr-TR') }}</span>
        </button>
        <p v-if="viewingId === item.evidenceId && viewedContent[item.evidenceId]" class="mt-1.5 whitespace-pre-wrap text-stone-700">
          {{ viewedContent[item.evidenceId] }}
        </p>
      </div>
    </div>
    <p v-else-if="!loading" class="text-xs text-stone-400">Henüz kanıt eklenmedi.</p>
  </div>
</template>
