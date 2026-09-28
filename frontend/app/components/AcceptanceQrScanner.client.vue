<script setup lang="ts">
import { ref, onUnmounted } from 'vue'
import { PhCamera, PhCircleNotch } from '@phosphor-icons/vue'
import { isBarcodeScannerSupported, startBarcodeScanner, type BarcodeScanHandle } from '@/composables/useBarcodeScanner'

const emit = defineEmits<{ scanned: [value: string] }>()

const supported = isBarcodeScannerSupported()
const video = ref<HTMLVideoElement | null>(null)
const scanning = ref(false)
const error = ref('')
let handle: BarcodeScanHandle | null = null

async function start() {
  if (!supported || !video.value) return
  error.value = ''
  scanning.value = true
  try {
    handle = await startBarcodeScanner(video.value, (value) => {
      scanning.value = false
      emit('scanned', value)
    })
  } catch {
    scanning.value = false
    error.value = 'Kamera erişimi verilmedi veya kullanılamıyor. Kopyala-yapıştır alanını kullanın.'
  }
}

function stop() {
  handle?.stop()
  handle = null
  scanning.value = false
}

onUnmounted(stop)
</script>

<template>
  <div v-if="supported" class="space-y-2">
    <div v-if="scanning" class="overflow-hidden rounded-lg border border-stone-200 bg-black">
      <video ref="video" class="aspect-square w-full object-cover" muted playsinline />
    </div>
    <button type="button" class="btn-secondary w-full justify-center" @click="scanning ? stop() : start()">
      <PhCircleNotch v-if="scanning && !video" class="size-4 animate-spin" />
      <PhCamera v-else class="size-4" />
      {{ scanning ? 'Taramayı durdur' : 'QR ile Tara' }}
    </button>
    <p v-if="error" class="text-xs text-red-600">{{ error }}</p>
  </div>
</template>
