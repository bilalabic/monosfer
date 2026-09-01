<script setup lang="ts">
import { ref, computed } from 'vue'
import { PhX as X, PhWarningCircle as AlertCircle, PhConfetti } from '@phosphor-icons/vue'
import { useDeliveryStore } from '@/stores/useDeliveryStore'
import { useWalletStore } from '@/stores/useWalletStore'

const props = defineProps<{ deliveryId: string; maxBudget: number }>()
const emit = defineEmits<{ close: []; success: [] }>()

const store = useDeliveryStore()
const wallet = useWalletStore()

const tokenAmount = ref<number | null>(null)
const estimatedTime = ref('')
const collateral = ref<number | null>(null)
const submitting = ref(false)
const submitted = ref(false)
const errorMsg = ref('')

const delivery = computed(() => store.getDelivery(props.deliveryId))
const alreadyBid = computed(() => delivery.value?.bids.some(b => b.courierId === wallet.address.toLowerCase()))

function handleAmountInput(e: Event) {
  const val = Number((e.target as HTMLInputElement).value)
  tokenAmount.value = val || null
  collateral.value = val ? Math.ceil(val * 0.2) : null
}

async function submit() {
  if (!tokenAmount.value || !estimatedTime.value) return
  errorMsg.value = ''
  submitting.value = true
  try {
    await store.addBid(props.deliveryId, {
      courierId: wallet.address.toLowerCase(),
      courierName: wallet.displayAddress() || 'Sen',
      courierAvatar: '',
      courierRating: 0,
      courierDeliveries: 0,
      tokenAmount: tokenAmount.value,
      estimatedTime: estimatedTime.value,
    })
    submitted.value = true
    setTimeout(() => emit('success'), 1400)
  } catch (e: unknown) {
    errorMsg.value = (e as { message?: string })?.message ?? 'Bir hata oluştu'
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <Teleport to="body">
    <div class="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div class="absolute inset-0 bg-stone-900/40 backdrop-blur-sm" @click="emit('close')" />

      <div class="relative w-full max-w-sm rounded-2xl border border-stone-200 bg-white p-6 shadow-xl">
        <!-- Header -->
        <div class="mb-5 flex items-center justify-between">
          <div>
            <h2 class="text-base font-semibold text-stone-900">Teklif Ver</h2>
            <p class="text-xs text-stone-400">Teklif + %20 teminat yatır</p>
          </div>
          <button class="flex size-8 items-center justify-center rounded-lg border border-stone-200 text-stone-400 hover:text-stone-700" @click="emit('close')">
            <X class="size-4" weight="bold" />
          </button>
        </div>

        <!-- Success -->
        <div v-if="submitted" class="py-6 text-center">
          <PhConfetti class="mx-auto mb-3 size-12 text-green-500" weight="duotone" />
          <h3 class="font-semibold text-green-600">Teklif Verildi!</h3>
          <p class="mt-1 text-sm text-stone-500">Müşterinin seçmesi bekleniyor.</p>
        </div>

        <!-- Already bid warning -->
        <div v-else-if="alreadyBid" class="py-6 text-center">
          <p class="text-2xl mb-2">🔒</p>
          <p class="font-semibold text-stone-700">Bu teslimat için zaten teklif verdiniz.</p>
          <button class="mt-4 text-sm text-stone-500 underline" @click="emit('close')">Kapat</button>
        </div>

        <!-- Form -->
        <div v-else class="space-y-4">
          <div v-if="errorMsg" class="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-xs text-red-700">{{ errorMsg }}</div>
          <div>
            <label class="mb-1.5 block text-sm font-medium text-stone-700">Token Miktarı (MON)</label>
            <div class="relative">
              <input
                type="number"
                :max="maxBudget"
                min="1"
                placeholder="Örn: 15"
                class="input pr-14"
                @input="handleAmountInput"
              />
              <span class="absolute right-3.5 top-1/2 -translate-y-1/2 text-xs font-semibold text-stone-400">MON</span>
            </div>
            <p class="mt-1 text-xs text-stone-400">Maks: {{ maxBudget }} MON</p>
          </div>

          <div>
            <label class="mb-1.5 block text-sm font-medium text-stone-700">Tahmini Süre</label>
            <input v-model="estimatedTime" type="text" placeholder="Örn: 45 dk" class="input" />
          </div>

          <div v-if="collateral" class="flex items-start gap-2 rounded-lg border border-amber-200 bg-amber-50 p-3">
            <AlertCircle class="mt-0.5 size-4 shrink-0 text-amber-600" weight="fill" />
            <p class="text-xs text-amber-700">
              <strong>{{ collateral }} MON teminat</strong> kilitlenecek. Teslimatı tamamlarsan iade edilir.
            </p>
          </div>

          <button
            :disabled="!tokenAmount || !estimatedTime || submitting || !!alreadyBid"
            class="btn-primary w-full justify-center disabled:opacity-40 disabled:cursor-not-allowed"
            @click="submit"
          >
            {{ submitting ? 'İşleniyor...' : 'Teklifi Onayla' }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
