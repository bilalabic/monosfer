<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { formatEther } from 'viem'
import { PhX as X, PhWarningCircle as AlertCircle, PhConfetti } from '@phosphor-icons/vue'
import { useDeliveryStore } from '@/stores/useDeliveryStore'
import { useWalletStore } from '@/stores/useWalletStore'

const props = defineProps<{ deliveryId: string; maxBudget: number }>()
const emit = defineEmits<{ close: []; success: [] }>()

const store = useDeliveryStore()
const wallet = useWalletStore()

const tokenAmount = ref<number | null>(null)
const returnAmount = ref<number | null>(null)
const estimatedTime = ref('')
const requiredStake = ref(0n)
const stakeLoading = ref(true)
const submitting = ref(false)
const submitted = ref(false)
const errorMsg = ref('')

const delivery = computed(() => store.getDelivery(props.deliveryId))
const alreadyBid = computed(() => delivery.value?.bids.some(b => b.active && b.courierId === wallet.address.toLowerCase()))
const requiredStakeMon = computed(() => Number(formatEther(requiredStake.value)))

function handleAmountInput(e: Event) {
  const val = Number((e.target as HTMLInputElement).value)
  tokenAmount.value = val || null
}

onMounted(async () => {
  try {
    requiredStake.value = (await store.bidStakeRequirement()).requiredDeposit
  } catch (error) {
    errorMsg.value = error instanceof Error ? error.message : 'Kurye teminatı okunamadı'
  } finally {
    stakeLoading.value = false
  }
})

async function submit() {
  const etaMinutes = Number.parseInt(estimatedTime.value)
  if (!tokenAmount.value || !returnAmount.value || !Number.isSafeInteger(etaMinutes) || etaMinutes <= 0) return
  errorMsg.value = ''
  submitting.value = true
  try {
    await store.addBid(props.deliveryId, {
      tokenAmount: tokenAmount.value,
      returnAmount: returnAmount.value,
      estimatedMinutes: etaMinutes,
      requiredStake: requiredStake.value,
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

      <div class="bid-dialog relative max-h-[calc(100dvh-2rem)] w-full max-w-md overflow-y-auto rounded-3xl border border-stone-200 bg-white p-6 shadow-xl" role="dialog" aria-modal="true" aria-labelledby="bid-dialog-title">
        <!-- Header -->
        <div class="mb-5 flex items-center justify-between">
          <div>
            <p class="page-eyebrow">Yeni bir yolculuğa katıl</p>
            <h2 id="bid-dialog-title" class="font-heading text-2xl font-bold tracking-tight text-stone-900">Teklif Ver</h2>
            <p class="text-xs text-stone-400">Teklif ve zincir teminatı</p>
          </div>
          <button aria-label="Teklif penceresini kapat" class="flex size-8 items-center justify-center rounded-lg border border-stone-200 text-stone-400 hover:text-stone-700" @click="emit('close')">
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
            <label class="mb-1.5 block text-sm font-medium text-stone-700">İade Ücreti (MON)</label>
            <div class="relative">
              <input v-model.number="returnAmount" type="number" min="0.000001" step="any" placeholder="Örn: 10" class="input pr-14" />
              <span class="absolute right-3.5 top-1/2 -translate-y-1/2 text-xs font-semibold text-stone-400">MON</span>
            </div>
          </div>

          <div>
            <label class="mb-1.5 block text-sm font-medium text-stone-700">Tahmini Süre</label>
            <input v-model="estimatedTime" type="number" min="1" step="1" placeholder="Örn: 45" class="input" />
            <p class="mt-1 text-xs text-stone-400">Dakika cinsinden</p>
          </div>

          <div v-if="stakeLoading || requiredStake > 0n" class="flex items-start gap-2 rounded-lg border border-amber-200 bg-amber-50 p-3">
            <AlertCircle class="mt-0.5 size-4 shrink-0 text-amber-600" weight="fill" />
            <p class="text-xs text-amber-700">
              <span v-if="stakeLoading">Zincir teminatı kontrol ediliyor…</span>
              <span v-else><strong>{{ requiredStakeMon }} MON stake</strong> eksik. Tekliften önce ayrı bir cüzdan işlemiyle yatırılacak.</span>
            </p>
          </div>

          <button
            :disabled="!tokenAmount || !returnAmount || !estimatedTime || submitting || stakeLoading || !!alreadyBid"
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
