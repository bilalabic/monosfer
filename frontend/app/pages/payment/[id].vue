<script setup lang="ts">
definePageMeta({ requiresAuth: true })

import { computed, ref } from 'vue'
import { formatEther } from 'viem'
import { PhArrowLeft, PhCheckCircle, PhCircleNotch, PhLockKey, PhShieldCheck } from '@phosphor-icons/vue'
import { useDeliveryStore } from '@/stores/useDeliveryStore'
import { useWalletStore } from '@/stores/useWalletStore'
import { deliveryStateLabel } from '@/utils/delivery-state'
import { MONAD_TESTNET } from '@/config/chain'

const route = useRoute()
const router = useRouter()
const deliveries = useDeliveryStore()
const wallet = useWalletStore()
const processing = ref(false)
const error = ref('')
const txHash = ref('')
const fundedAmount = ref('')

if (!deliveries.getDelivery(route.params.id as string)) {
  await deliveries.fetchDelivery(route.params.id as string)
}

const delivery = computed(() => deliveries.getDelivery(route.params.id as string))
const isOwner = computed(() => delivery.value?.senderId === wallet.address.toLowerCase())
const alreadyFunded = computed(() => delivery.value?.customerFunded ?? false)
const explorerUrl = computed(() => txHash.value && MONAD_TESTNET.explorer ? `${MONAD_TESTNET.explorer}/tx/${txHash.value}` : '')

async function fund() {
  if (!delivery.value || !isOwner.value || alreadyFunded.value || processing.value) return
  processing.value = true
  error.value = ''
  try {
    const result = await deliveries.lockEscrow(delivery.value.id)
    txHash.value = result.hash
    fundedAmount.value = formatEther(result.value)
    await wallet.fetchBalance()
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : 'Müşteri fonlaması başarısız oldu'
  } finally {
    processing.value = false
  }
}
</script>

<template>
  <div class="page-shell page-shell--narrow">
    <button class="mb-6 flex items-center gap-1.5 text-sm text-stone-500 hover:text-stone-900" @click="router.back()">
      <PhArrowLeft class="size-4" weight="bold" /> Geri
    </button>

    <div v-if="!delivery" class="py-20 text-center text-stone-500">Teslimat bulunamadı.</div>
    <div v-else-if="!isOwner" class="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">
      Bu fonlama işlemini yalnız teslimatı oluşturan cüzdan yapabilir.
    </div>
    <div v-else class="space-y-5">
      <page-header compact eyebrow="Ödemen güvence altında" title="Müşteri Escrow Payı" description="Teslimat tutarını akıllı sözleşmede kilitle. Ödemen, teslimat tamamlanana kadar koruma altında kalsın." />

      <div class="card rounded-xl bg-white p-5">
        <div class="flex items-center justify-between">
          <span class="text-sm text-stone-500">Teslimat</span>
          <span class="font-semibold text-stone-900">#{{ delivery.id }}</span>
        </div>
        <div class="mt-3 flex items-center justify-between">
          <span class="text-sm text-stone-500">Durum</span>
          <span class="font-semibold text-stone-900">{{ deliveryStateLabel(delivery.chainState) }}</span>
        </div>
        <div class="mt-3 flex items-center justify-between">
          <span class="text-sm text-stone-500">Bakiye</span>
          <span class="font-semibold text-stone-900">{{ wallet.balance }} MON</span>
        </div>
      </div>

      <div class="flex gap-3 rounded-xl border border-orange-200 bg-orange-50 p-4">
        <PhShieldCheck class="mt-0.5 size-5 shrink-0 text-orange-500" weight="duotone" />
        <p class="text-xs leading-relaxed text-stone-600">
          Monad gas ücreti gas limitine göre alınır. Uygulama sözleşme çağrısını simüle eder, tahmine en fazla %10 güvenlik payı ekler.
        </p>
      </div>

      <div v-if="alreadyFunded || txHash" class="rounded-xl border border-green-200 bg-green-50 p-4">
        <p class="flex items-center gap-2 text-sm font-semibold text-green-700">
          <PhCheckCircle class="size-5" weight="fill" /> Müşteri payı fonlandı<span v-if="fundedAmount">: {{ fundedAmount }} MON</span>
        </p>
        <a v-if="explorerUrl" :href="explorerUrl" target="_blank" rel="noopener noreferrer" class="mt-2 block text-xs text-orange-700 underline">
          İşlemi explorer'da aç
        </a>
      </div>

      <button class="btn-primary w-full justify-center" :disabled="processing || alreadyFunded" @click="fund">
        <PhCircleNotch v-if="processing" class="size-4 animate-spin" weight="bold" />
        <PhLockKey v-else class="size-4" weight="bold" />
        {{ processing ? 'İşlem onaylanıyor…' : alreadyFunded ? 'Müşteri payı zaten fonlandı' : 'Cüzdanla Fonla' }}
      </button>
      <p v-if="error" class="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">{{ error }}</p>
    </div>
  </div>
</template>
