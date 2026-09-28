<script setup lang="ts">
import { ref, watch, onMounted } from 'vue'
import { renderAcceptanceQrCode } from '@/composables/useQrCode'

const props = defineProps<{ payload: string }>()

const canvas = ref<HTMLCanvasElement | null>(null)
const error = ref('')

async function draw() {
  if (!canvas.value || !props.payload) return
  try {
    await renderAcceptanceQrCode(canvas.value, props.payload)
    error.value = ''
  } catch {
    error.value = 'QR kod oluşturulamadı. Kopyala-yapıştır alanını kullanın.'
  }
}

onMounted(draw)
watch(() => props.payload, draw)
</script>

<template>
  <div class="flex flex-col items-center gap-2">
    <canvas ref="canvas" class="rounded-lg border border-stone-200" />
    <p v-if="error" class="text-xs text-red-600">{{ error }}</p>
    <p v-else class="text-xs text-stone-500">Kuryenin cihazıyla bu QR kodu okutun.</p>
  </div>
</template>
