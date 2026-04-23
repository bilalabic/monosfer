<script setup lang="ts">
import { ref, computed, watchEffect } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  PhLockKey, PhCheckCircle, PhArrowLeft, PhShieldCheck,
  PhWarning, PhArrowRight, PhCopy, PhCircleNotch
} from '@phosphor-icons/vue'
import { useDeliveryStore } from '@/stores/useDeliveryStore'
import { useWalletStore } from '@/stores/useWalletStore'
import { MONAD_TESTNET } from '@/config/chain'

const route = useRoute()
const router = useRouter()
const dStore = useDeliveryStore()
const wallet = useWalletStore()

const delivery = computed(() => dStore.getDelivery(route.params.id as string))
const isEscrowLocked = computed(() => (delivery.value?.escrowAmount || 0) > 0)

const isOwner = computed(() =>
  !!wallet.address && !!delivery.value?.senderId &&
  wallet.address.toLowerCase() === delivery.value.senderId
)

watchEffect(() => {
  if (delivery.value && !isOwner.value) {
    router.replace('/deliveries')
  }
})

const GAS = 0.00023
type Step = 'review' | 'signing' | 'confirming' | 'success'
const step = ref<Step>('review')
const txHash = ref('')
const blockNum = ref(0)
const confirmations = ref(0)
const copied = ref(false)

const escrowTokenAmount = computed(() => {
  if (!delivery.value) return 0
  return isEscrowLocked.value ? delivery.value.escrowAmount : delivery.value.maxBudget
})
const sufficient = computed(() => wallet.balance >= GAS)
const txExplorerUrl = computed(() =>
  txHash.value ? `https://testnet.monadexplorer.com/tx/${txHash.value}` : '',
)

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

async function sendAnchorTx(): Promise<{ hash: string; blockNumber: number }> {
  const ethereum = (window as unknown as { ethereum?: { request: (args: { method: string; params?: unknown[] }) => Promise<unknown> } }).ethereum
  if (!ethereum || !wallet.address) throw new Error('Cuzdan bagli degil')
  await ensureMonadTestnet()

  const hash = await ethereum.request({
    method: 'eth_sendTransaction',
    params: [{
      from: wallet.address,
      to: wallet.address,
      value: '0x0',
    }],
  }) as string

  while (true) {
    const receipt = await ethereum.request({
      method: 'eth_getTransactionReceipt',
      params: [hash],
    }) as { status?: string; blockNumber?: string } | null
    if (receipt?.status === '0x1' && receipt.blockNumber) {
      return { hash, blockNumber: Number.parseInt(receipt.blockNumber, 16) }
    }
    await wait(1200)
  }
}

async function pay() {
  if (!delivery.value || !sufficient.value || isEscrowLocked.value) return
  step.value = 'signing'
  await wait(600)

  step.value = 'confirming'
  const sent = await sendAnchorTx()
  txHash.value = sent.hash
  confirmations.value = 0

  for (let i = 1; i <= 3; i++) {
    await wait(1100)
    confirmations.value = i
    blockNum.value = sent.blockNumber + i - 1
  }

  await wallet.fetchBalance()
  await dStore.lockEscrow(delivery.value.id, txHash.value)
  step.value = 'success'
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
      v-if="step === 'review'"
      class="mb-6 flex items-center gap-1.5 text-sm text-stone-500 hover:text-stone-900 transition"
      @click="router.back()"
    >
      <PhArrowLeft class="size-4" weight="bold" /> Geri
    </button>

    <div v-if="!delivery" class="py-20 text-center text-stone-500">Teslimat bulunamadı.</div>

    <template v-else>
      <!-- REVIEW -->
      <div v-if="step === 'review'" class="space-y-5">
        <div>
          <p class="mb-1 text-xs font-semibold uppercase tracking-widest text-orange-500">Escrow Ödemesi</p>
          <h1 class="text-2xl font-bold text-stone-900">{{ isEscrowLocked ? 'Ödeme Kilitli' : 'Ödemeyi Kilitle' }}</h1>
          <p class="mt-1 text-sm text-stone-500">
            {{ isEscrowLocked ? 'Bu teslimat için ödeme zaten escrow hesabında bekliyor.' : 'Ödemeniz Monad akıllı sözleşmesinde kilitlenecek, teslimat tamamlandığında kurye alacak.' }}
          </p>
        </div>

        <!-- Delivery summary -->
        <div class="card rounded-xl bg-white p-5">
          <p class="mb-3 text-xs font-semibold uppercase tracking-wide text-stone-400">Teslimat</p>
          <p class="mb-3 text-sm font-semibold text-stone-900">{{ delivery.title }}</p>
          <div class="space-y-2">
            <div class="flex items-center gap-2.5">
              <span class="size-2 shrink-0 rounded-full bg-green-500" />
              <span class="text-xs text-stone-500">{{ delivery.pickupAddress }}</span>
            </div>
            <div class="ml-1 h-3 w-px bg-stone-200" />
            <div class="flex items-center gap-2.5">
              <span class="size-2 shrink-0 rounded-full bg-red-400" />
              <span class="text-xs text-stone-500">{{ delivery.dropoffAddress }}</span>
            </div>
          </div>
        </div>

        <!-- Payment breakdown -->
        <div class="card rounded-xl bg-white p-5">
          <p class="mb-4 text-xs font-semibold uppercase tracking-wide text-stone-400">Ödeme Detayı</p>
          <div class="space-y-3 text-sm">
            <div class="flex items-center justify-between">
              <span class="text-stone-600">Teslimat Ucreti (Escrow)</span>
              <span class="font-semibold text-stone-900">{{ escrowTokenAmount }} MON</span>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-stone-400">Gas Ücreti (tahmini)</span>
              <span class="text-stone-400">≈ {{ GAS }} MON</span>
            </div>
            <div class="flex items-center justify-between border-t border-stone-100 pt-3">
              <span class="font-semibold text-stone-900">Escrow Token</span>
              <span class="font-semibold text-stone-900">{{ escrowTokenAmount }} MON</span>
            </div>
          </div>
        </div>

        <!-- Balance check -->
        <div
          :class="[
            'flex items-center justify-between rounded-xl border p-4',
            sufficient ? 'border-stone-200 bg-stone-50' : 'border-red-200 bg-red-50'
          ]"
        >
          <div>
            <p class="text-xs text-stone-400">Cüzdan Bakiyesi</p>
            <p class="font-bold text-stone-900">{{ wallet.balance.toFixed(2) }} MON</p>
          </div>
          <div v-if="!sufficient" class="flex items-center gap-1.5 text-xs text-red-600">
            <PhWarning class="size-4" weight="fill" /> Yetersiz Bakiye
          </div>
          <div v-else class="flex items-center gap-1.5 text-xs text-green-600">
            <PhCheckCircle class="size-4" weight="fill" /> Yeterli
          </div>
        </div>

        <!-- Info -->
        <div class="flex gap-3 rounded-xl border border-orange-200 bg-orange-50 p-4">
          <PhShieldCheck class="mt-0.5 size-5 shrink-0 text-orange-500" weight="duotone" />
          <p class="text-xs leading-relaxed text-stone-600">
            Paranız Monad'ın hızlı finality özelliğiyle (~800ms) escrow sözleşmesine kilitlenir.
            Kurye teslimatı tamamlamadan ödeme serbest kalmaz.
          </p>
        </div>

        <button
          :disabled="!sufficient || isEscrowLocked"
          class="btn-primary w-full justify-center disabled:opacity-50"
          @click="pay"
        >
          <PhLockKey class="size-4" weight="bold" />
          {{ isEscrowLocked ? 'Zaten Kilitli' : sufficient ? `${escrowTokenAmount} MON Escrow Kaydet` : 'Gas icin MON yetersiz' }}
        </button>
      </div>

      <!-- SIGNING -->
      <div v-else-if="step === 'signing'" class="flex min-h-[60vh] flex-col items-center justify-center gap-6 text-center">
        <div class="relative">
          <div class="flex size-20 items-center justify-center rounded-full bg-orange-100">
            <PhLockKey class="size-10 text-orange-500" weight="duotone" />
          </div>
          <div class="absolute -right-1 -top-1 flex size-7 items-center justify-center rounded-full bg-orange-400">
            <PhCircleNotch class="size-4 animate-spin text-white" weight="bold" />
          </div>
        </div>
        <div>
          <h2 class="text-lg font-bold text-stone-900">İmza Bekleniyor</h2>
          <p class="mt-1 text-sm text-stone-500">Cuzdaninizda Monad Testnet islemine imza verin</p>
        </div>
        <div class="w-full max-w-xs space-y-2 rounded-xl border border-stone-200 bg-stone-50 p-4 text-left">
          <p class="text-xs font-semibold text-stone-500">İşlem Özeti</p>
          <div class="flex justify-between text-xs">
            <span class="text-stone-400">Kontrat</span>
            <span class="font-mono text-stone-600">
              {{ `${MONAD_TESTNET.contracts.escrow.slice(0, 6)}...${MONAD_TESTNET.contracts.escrow.slice(-4)}` }}
            </span>
          </div>
          <div class="flex justify-between text-xs">
            <span class="text-stone-400">Miktar</span>
            <span class="font-semibold text-stone-900">{{ escrowTokenAmount }} MON</span>
          </div>
          <div class="flex justify-between text-xs">
            <span class="text-stone-400">Gas</span>
            <span class="text-stone-500">≈ {{ GAS }} MON</span>
          </div>
          <div class="flex justify-between text-xs">
            <span class="text-stone-400">Ağ</span>
            <span class="font-semibold text-purple-600">Monad Testnet</span>
          </div>
        </div>
      </div>

      <!-- CONFIRMING -->
      <div v-else-if="step === 'confirming'" class="flex min-h-[60vh] flex-col items-center justify-center gap-6 text-center">
        <div>
          <div class="mb-5 flex justify-center gap-2">
            <div
              v-for="i in 3"
              :key="i"
              :class="[
                'size-3 rounded-full transition-all duration-500',
                i <= confirmations ? 'bg-orange-500 scale-125' : 'bg-stone-200'
              ]"
            />
          </div>
          <h2 class="text-lg font-bold text-stone-900">Blok Onayı Bekleniyor</h2>
          <p class="mt-1 text-sm text-stone-500">{{ confirmations }}/3 onay</p>
          <p class="mt-1 text-xs text-stone-400">Blok #{{ blockNum || '…' }}</p>
          <p class="mt-3 text-xs text-purple-600">⚡ Monad — 400ms blok süresi</p>
        </div>

        <div class="w-full max-w-xs rounded-xl border border-stone-200 bg-stone-50 p-4 text-left">
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
        <div class="flex size-20 items-center justify-center rounded-full bg-green-100">
          <PhCheckCircle class="size-12 text-green-500" weight="fill" />
        </div>
        <div>
          <h2 class="text-2xl font-bold text-stone-900">Ödeme Kilitlendi!</h2>
          <p class="mt-1 text-sm text-stone-500">
            {{ escrowTokenAmount }} MON escrow kaydi backend'e islendi ve tx testnete yazildi
          </p>
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
            <span class="text-stone-500">Blok Numarası</span>
            <span class="font-mono font-semibold text-stone-900">#{{ blockNum }}</span>
          </div>
          <div class="flex justify-between rounded-xl border border-green-200 bg-green-50 p-3 text-sm">
            <span class="text-stone-500">Onaylar</span>
            <span class="font-semibold text-green-600">3 / 3 ✓</span>
          </div>
          <div class="flex justify-between rounded-xl border border-purple-200 bg-purple-50 p-3 text-sm">
            <span class="text-stone-500">Ağ</span>
            <span class="font-semibold text-purple-700">Monad Testnet</span>
          </div>
        </div>

        <div class="flex w-full max-w-xs flex-col gap-2">
          <button
            class="btn-primary w-full justify-center"
            @click="router.push(`/delivery/${delivery.id}`)"
          >
            <PhArrowRight class="size-4" weight="bold" />
            Teslimat Detayına Git
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
