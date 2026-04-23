<script setup lang="ts">
import { ref, computed, onMounted, watchEffect } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  PhArrowLeft, PhCheckCircle, PhPackage, PhCoins,
  PhQrCode, PhCopy, PhArrowRight,
  PhTruck, PhMapPin
} from '@phosphor-icons/vue'
import { useDeliveryStore } from '@/stores/useDeliveryStore'
import { useWalletStore } from '@/stores/useWalletStore'
import { MONAD_TESTNET } from '@/config/chain'
import QrCode from '@/components/QrCode.vue'
import TokenAmount from '@/components/TokenAmount.vue'

const route = useRoute()
const router = useRouter()
const dStore = useDeliveryStore()
const wallet = useWalletStore()

const delivery = computed(() => dStore.getDelivery(route.params.id as string))
const assignedBid = computed(() =>
  delivery.value?.bids.find(b => b.id === delivery.value?.selectedBidId)
)

const isAssignedCourier = computed(() =>
  !!wallet.address && !!delivery.value?.assignedCourierId &&
  wallet.address.toLowerCase() === delivery.value.assignedCourierId.toLowerCase()
)

onMounted(() => {
  if (dStore.deliveries.length === 0) dStore.loadDeliveries()
})

watchEffect(() => {
  if (delivery.value && !isAssignedCourier.value) {
    router.replace('/deliveries')
  }
})

const verifyCode = computed(() => {
  const id = delivery.value?.id ?? 'x'
  const sum = id.split('').reduce((a, c) => a + c.charCodeAt(0), 0)
  return `MON-${id.toUpperCase()}-${sum.toString(16).toUpperCase().padStart(4, '0')}`
})

const appOrigin = computed(() => {
  if (typeof window === 'undefined') return ''
  return window.location.origin
})
const pickupConfirmUrl = computed(() =>
  `${appOrigin.value}/delivery/${delivery.value?.id}/confirm?step=pickup&code=${encodeURIComponent(verifyCode.value)}`,
)
const deliveryConfirmUrl = computed(() =>
  `${appOrigin.value}/delivery/${delivery.value?.id}/confirm?step=delivery&code=${encodeURIComponent(`${verifyCode.value}-DEL`)}`,
)
const pickupConfirmed = computed(() =>
  delivery.value?.timeline.some(step => step.step === 'pickup' && step.completed),
)

type Phase = 'pickup_qr' | 'pickup_confirming' | 'delivery_qr' | 'payment_confirming' | 'success'
const phase = ref<Phase>('pickup_qr')
const txHash = ref('')
const copied = ref(false)
const earnedAmount = computed(() => assignedBid.value?.tokenAmount ?? 0)
const txExplorerUrl = computed(() =>
  txHash.value ? `https://testnet.monadexplorer.com/tx/${txHash.value}` : '',
)

watchEffect(() => {
  if (delivery.value?.status === 'completed' && phase.value !== 'payment_confirming') {
    phase.value = 'success'
  } else if (pickupConfirmed.value && phase.value === 'pickup_qr') {
    phase.value = 'delivery_qr'
  }
})

async function ensureMonadTestnet() {
  const ethereum = (window as unknown as { ethereum?: { request: (args: { method: string; params?: unknown[] }) => Promise<unknown> } }).ethereum
  if (!ethereum) throw new Error('MetaMask bulunamadi')
  const currentChain = await ethereum.request({ method: 'eth_chainId' }) as string
  if (currentChain === MONAD_TESTNET.chainIdHex) return
  await ethereum.request({
    method: 'wallet_switchEthereumChain',
    params: [{ chainId: MONAD_TESTNET.chainIdHex }],
  })
}

async function sendAnchorTx(): Promise<string> {
  const ethereum = (window as unknown as { ethereum?: { request: (args: { method: string; params?: unknown[] }) => Promise<unknown> } }).ethereum
  if (!ethereum || !wallet.address) throw new Error('Cuzdan bagli degil')
  await ensureMonadTestnet()
  const hash = await ethereum.request({
    method: 'eth_sendTransaction',
    params: [{ from: wallet.address, to: wallet.address, value: '0x0' }],
  }) as string

  while (true) {
    const receipt = await ethereum.request({
      method: 'eth_getTransactionReceipt',
      params: [hash],
    }) as { status?: string } | null
    if (receipt?.status === '0x1') return hash
    await wait(1200)
  }
}

async function confirmPickup() {
  phase.value = 'pickup_confirming'
  const hash = await sendAnchorTx()
  txHash.value = hash
  await dStore.confirmPickup(delivery.value!.id, hash)
  phase.value = 'delivery_qr'
}

async function completeDelivery() {
  phase.value = 'payment_confirming'
  const hash = await sendAnchorTx()
  txHash.value = hash
  await wallet.fetchBalance()
  await dStore.completeDelivery(delivery.value!.id, hash)
  phase.value = 'success'
}

async function refreshDelivery() {
  await dStore.loadDeliveries()
}

function copyHash() {
  navigator.clipboard.writeText(txHash.value)
  copied.value = true
  setTimeout(() => (copied.value = false), 2000)
}

const wait = (ms: number) => new Promise(r => setTimeout(r, ms))
</script>

<template>
  <div class="mx-auto max-w-lg px-5 py-10 sm:px-8">
    <button
      v-if="phase === 'pickup_qr'"
      class="mb-6 flex items-center gap-1.5 text-sm text-stone-500 hover:text-stone-900 transition"
      @click="router.back()"
    >
      <PhArrowLeft class="size-4" weight="bold" /> Geri
    </button>

    <div v-if="!delivery || !assignedBid" class="py-20 text-center">
      <p class="text-stone-500">Aktif teslimat bulunamadı.</p>
      <button class="btn-primary mt-4" @click="router.push('/deliveries')">Teslimatlar</button>
    </div>

    <template v-else>
      <!-- PICKUP QR -->
      <div v-if="phase === 'pickup_qr'" class="space-y-5">
        <div>
          <p class="mb-1 text-xs font-semibold uppercase tracking-widest text-orange-500">Kurye Paneli</p>
          <h1 class="text-2xl font-bold text-stone-900">Paket Teslim Alma</h1>
          <p class="mt-1 text-sm text-stone-500">
            Göndericideki QR kodu okutarak paketi teslim aldığını onayla.
          </p>
        </div>

        <!-- Delivery info -->
        <div class="card rounded-xl bg-white p-4">
          <p class="mb-3 text-xs font-semibold uppercase tracking-wide text-stone-400">Teslimat Bilgisi</p>
          <p class="mb-3 text-sm font-semibold text-stone-900">{{ delivery.title }}</p>
          <div class="space-y-2">
            <div class="flex items-center gap-2.5">
              <PhMapPin class="size-3.5 shrink-0 text-green-500" weight="fill" />
              <span class="text-xs text-stone-500">Alış: {{ delivery.pickupAddress }}</span>
            </div>
            <div class="flex items-center gap-2.5">
              <PhMapPin class="size-3.5 shrink-0 text-red-400" weight="fill" />
              <span class="text-xs text-stone-500">Teslim: {{ delivery.dropoffAddress }}</span>
            </div>
          </div>
        </div>

        <!-- Pickup instruction -->
        <div class="flex flex-col items-center gap-4 rounded-xl border-2 border-dashed border-orange-200 bg-orange-50 p-6 text-center">
          <div class="flex items-center gap-2 text-sm font-semibold text-orange-700">
            <PhQrCode class="size-4" weight="bold" />
            Göndericideki QR'ı Okut
          </div>
          <div class="rounded-lg bg-white px-4 py-2 shadow-sm">
            <p class="text-center font-mono text-sm font-bold tracking-widest text-stone-900">{{ verifyCode }}</p>
            <p class="mt-0.5 text-center text-[10px] text-stone-400">Doğrulama Kodu</p>
          </div>
          <p class="max-w-xs text-xs leading-relaxed text-stone-600">
            Paketi teslim alırken ilan sahibinin teslimat detayındaki QR kodunu telefonunuzla okutun. Açılan sayfada onay verdiğinizde teslimat yola çıkar.
          </p>
        </div>

        <!-- Earnings preview -->
        <div class="flex items-center justify-between rounded-xl border border-stone-200 bg-stone-50 p-4">
          <div class="flex items-center gap-2">
            <PhCoins class="size-5 text-amber-500" weight="duotone" />
            <span class="text-sm text-stone-600">Teslimat Kazancı</span>
          </div>
          <TokenAmount :amount="earnedAmount" size="md" />
        </div>

        <a class="btn-primary w-full justify-center" :href="pickupConfirmUrl" target="_blank" rel="noopener">
          <PhPackage class="size-4" weight="bold" />
          QR Onay Sayfasını Aç
        </a>
        <button class="w-full rounded-lg border border-stone-200 py-2.5 text-sm text-stone-600 transition hover:bg-stone-50" @click="refreshDelivery">
          Durumu Yenile
        </button>
      </div>

      <!-- PICKUP CONFIRMING -->
      <div v-else-if="phase === 'pickup_confirming'" class="flex min-h-[60vh] flex-col items-center justify-center gap-6 text-center">
        <div class="relative">
          <div class="flex size-20 items-center justify-center rounded-full bg-orange-100">
            <PhPackage class="size-10 text-orange-500" weight="duotone" />
          </div>
          <div class="absolute -right-1 -top-1 flex size-7 items-center justify-center rounded-full bg-orange-400">
            <PhCircleNotch class="size-4 animate-spin text-white" weight="bold" />
          </div>
        </div>
        <div>
          <h2 class="text-lg font-bold text-stone-900">Teslim Alım Kaydediliyor</h2>
          <p class="mt-1 text-sm text-stone-500">Blockchain'e yazılıyor…</p>
          <p class="mt-2 text-xs text-purple-600">⚡ Monad — 400ms finality</p>
        </div>
      </div>

      <!-- DELIVERY QR -->
      <div v-else-if="phase === 'delivery_qr'" class="space-y-5">
        <div>
          <p class="mb-1 text-xs font-semibold uppercase tracking-widest text-green-600">Paket Yolda</p>
          <h1 class="text-2xl font-bold text-stone-900">Teslimat QR</h1>
          <p class="mt-1 text-sm text-stone-500">
            Alıcı bu QR kodu tarar, göndericinin verdiği teslim kodunu girer ve ödeme serbest kalır.
          </p>
        </div>

        <!-- Progress indicator -->
        <div class="flex items-center gap-3 rounded-xl border border-green-200 bg-green-50 p-3">
          <PhCheckCircle class="size-5 shrink-0 text-green-500" weight="fill" />
          <p class="text-xs text-stone-600">Paket teslim alındı. Şimdi {{ delivery.dropoffAddress }} adresine götür.</p>
        </div>

        <!-- QR Code -->
        <div class="flex flex-col items-center gap-4 rounded-xl border-2 border-dashed border-green-200 bg-green-50 p-6">
          <div class="flex items-center gap-2 text-sm font-semibold text-green-700">
            <PhTruck class="size-4" weight="bold" />
            Alıcı İçin — Teslimat QR
          </div>
          <div class="rounded-2xl bg-white p-3 shadow-md">
            <QrCode :value="deliveryConfirmUrl" :size="200" />
          </div>
          <div class="rounded-lg bg-white px-4 py-2 shadow-sm">
            <p class="text-center font-mono text-sm font-bold tracking-widest text-stone-900">{{ verifyCode }}-DEL</p>
            <p class="mt-0.5 text-center text-[10px] text-stone-400">QR Referansı</p>
          </div>
        </div>

        <!-- Earnings preview -->
        <div class="flex items-center justify-between rounded-xl border border-amber-200 bg-amber-50 p-4">
          <div>
            <p class="text-xs text-amber-600">Onaylandığında kazanacaksın</p>
            <div class="mt-0.5">
              <TokenAmount :amount="earnedAmount" size="md" />
            </div>
          </div>
          <PhCoins class="size-8 text-amber-400" weight="duotone" />
        </div>

        <a class="btn-primary w-full justify-center" :href="deliveryConfirmUrl" target="_blank" rel="noopener">
          <PhTruck class="size-4" weight="bold" />
          Alıcı Onay Sayfasını Aç
        </a>
        <button class="w-full rounded-lg border border-stone-200 py-2.5 text-sm text-stone-600 transition hover:bg-stone-50" @click="refreshDelivery">
          Durumu Yenile
        </button>
      </div>

      <!-- PAYMENT CONFIRMING -->
      <div v-else-if="phase === 'payment_confirming'" class="flex min-h-[60vh] flex-col items-center justify-center gap-6 text-center">
        <div class="relative">
          <div class="flex size-20 items-center justify-center rounded-full bg-amber-100">
            <PhCoins class="size-10 text-amber-500" weight="duotone" />
          </div>
          <div class="absolute -right-1 -top-1 flex size-7 items-center justify-center rounded-full bg-amber-400">
            <PhCircleNotch class="size-4 animate-spin text-white" weight="bold" />
          </div>
        </div>
        <div>
          <h2 class="text-lg font-bold text-stone-900">Ödeme Aktarılıyor</h2>
          <p class="mt-1 text-sm text-stone-500">Escrow serbest bırakılıyor...</p>
          <p class="mt-2 text-xs text-purple-600">⚡ Monad akıllı sözleşmesi çalışıyor</p>
        </div>
        <div v-if="txHash" class="w-full max-w-xs rounded-xl border border-stone-200 bg-stone-50 p-4 text-left">
          <p class="mb-2 text-xs font-semibold text-stone-500">TX Hash</p>
          <p class="break-all font-mono text-[10px] text-stone-600">{{ txHash }}</p>
          <a
            :href="txExplorerUrl"
            target="_blank"
            rel="noopener noreferrer"
            class="mt-2 inline-block text-[11px] font-semibold text-purple-600 hover:text-purple-500"
          >
            Explorer'da Gor
          </a>
        </div>
      </div>

      <!-- SUCCESS -->
      <div v-else class="flex min-h-[60vh] flex-col items-center gap-6 pt-10 text-center">
        <div class="flex size-24 items-center justify-center rounded-full bg-green-100">
          <PhCoins class="size-14 text-amber-500" weight="duotone" />
        </div>
        <div>
          <p class="text-xs font-semibold uppercase tracking-widest text-green-600">Ödeme Alındı</p>
          <h2 class="mt-1 text-3xl font-extrabold text-stone-900">{{ earnedAmount }} MON</h2>
          <p class="mt-1 text-sm text-stone-500">Cüzdanınıza başarıyla aktarıldı</p>
        </div>

        <div class="w-full max-w-xs space-y-3">
          <div class="rounded-xl border border-stone-200 bg-stone-50 p-4 text-left">
            <div class="mb-2 flex items-center justify-between">
              <p class="text-xs font-semibold text-stone-500">TX Hash</p>
              <button
                class="flex items-center gap-1 text-xs text-orange-600 transition hover:text-orange-500"
                @click="copyHash"
              >
                <PhCopy class="size-3" weight="bold" />
                {{ copied ? 'Kopyalandı!' : 'Kopyala' }}
              </button>
            </div>
            <p class="break-all font-mono text-[10px] text-stone-600">{{ txHash }}</p>
            <a
              :href="txExplorerUrl"
              target="_blank"
              rel="noopener noreferrer"
              class="mt-2 inline-block text-[11px] font-semibold text-purple-600 hover:text-purple-500"
            >
              Explorer'da Gor
            </a>
          </div>
          <div class="flex justify-between rounded-xl border border-green-200 bg-green-50 p-3 text-sm">
            <span class="text-stone-500">Yeni Bakiye</span>
            <span class="font-bold text-stone-900">{{ wallet.balance.toFixed(2) }} MON</span>
          </div>
          <div class="flex justify-between rounded-xl border border-purple-200 bg-purple-50 p-3 text-sm">
            <span class="text-stone-500">Ağ</span>
            <span class="font-semibold text-purple-700">Monad Testnet</span>
          </div>
        </div>

        <div class="flex w-full max-w-xs flex-col gap-2">
          <button class="btn-primary w-full justify-center" @click="router.push('/dashboard')">
            <PhArrowRight class="size-4" weight="bold" />
            Panele Dön
          </button>
          <button
            class="w-full rounded-lg border border-stone-200 py-2.5 text-sm text-stone-600 transition hover:bg-stone-50"
            @click="router.push('/deliveries')"
          >
            Tüm Teslimatlar
          </button>
        </div>
      </div>
    </template>
  </div>
</template>
