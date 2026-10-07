<script setup lang="ts">
definePageMeta({ requiresAuth: true })

import { computed, ref } from 'vue'
import { formatEther } from 'viem'
import { PhArrowLeft, PhCheckCircle, PhCircleNotch, PhPackage, PhTruck, PhWarning } from '@phosphor-icons/vue'
import { useDeliveryStore } from '@/stores/useDeliveryStore'
import { useWalletStore } from '@/stores/useWalletStore'
import { deliveryStateLabel } from '@/utils/delivery-state'
import AcceptanceQrScanner from '@/components/AcceptanceQrScanner.client.vue'

const route = useRoute()
const router = useRouter()
const deliveries = useDeliveryStore()
const wallet = useWalletStore()
const id = route.params.id as string

if (!deliveries.getDelivery(id)) await deliveries.fetchDelivery(id)

const delivery = computed(() => deliveries.getDelivery(id))
const isAssignedCourier = computed(() => delivery.value?.assignedCourierId === wallet.address.toLowerCase())
const indexerReady = computed(() => delivery.value?.indexing.status === 'ready')
const acceptancePackage = ref('')
const deliveryCode = ref('')
const processing = ref(false)
const error = ref('')
const message = ref('')

async function run(action: () => Promise<unknown>, success: string) {
  processing.value = true
  error.value = ''
  message.value = ''
  try {
    await action()
    message.value = success
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : 'İşlem başarısız oldu'
  } finally {
    processing.value = false
  }
}

async function fund() {
  if (!delivery.value) return
  await run(async () => {
    const result = await deliveries.fundCourier(delivery.value!.id)
    message.value = `${formatEther(result.value)} MON ek teminatla kurye payı fonlandı.`
  }, 'Kurye payı fonlandı.')
}

async function confirmPickup() {
  if (!delivery.value || !acceptancePackage.value.trim()) return
  await run(
    () => deliveries.confirmPickup(delivery.value!.id, acceptancePackage.value.trim()),
    'Paket devri zincirde doğrulandı.',
  )
  acceptancePackage.value = ''
}

async function confirmReturn() {
  if (!delivery.value || !acceptancePackage.value.trim()) return
  await run(
    () => deliveries.confirmReturn(delivery.value!.id, acceptancePackage.value.trim()),
    'İade zincirde doğrulandı.',
  )
  acceptancePackage.value = ''
}

async function submitPod() {
  if (!delivery.value || !deliveryCode.value.trim()) return
  await run(
    () => deliveries.completeDeliveryWithRecipientCode(delivery.value!.id, deliveryCode.value.trim()),
    'PoD attestation zincire gönderildi; itiraz penceresi açıldı.',
  )
  deliveryCode.value = ''
}
</script>

<template>
  <div class="page-shell page-shell--narrow">
    <button class="mb-6 flex items-center gap-1.5 text-sm text-stone-500 hover:text-stone-900" @click="router.back()">
      <PhArrowLeft class="size-4" weight="bold" /> Geri
    </button>

    <div v-if="!delivery" class="py-20 text-center text-stone-500">Teslimat bulunamadı.</div>
    <div v-else-if="!isAssignedCourier" class="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">
      Bu işlem yalnız finalized projection içindeki atanmış kurye tarafından yapılabilir.
    </div>
    <div v-else class="space-y-5">
      <page-header compact eyebrow="Kurye akışı" :title="`Teslimat #${delivery.id}`" :description="`Teslimat durumu: ${deliveryStateLabel(delivery.chainState)}`" />

      <section v-if="delivery.chainState === 'AwaitingFunding'" class="card space-y-4 rounded-xl bg-white p-5">
        <div class="flex gap-3">
          <PhTruck class="mt-0.5 size-6 shrink-0 text-orange-500" weight="duotone" />
          <p class="text-sm text-stone-600">Kurye teminatını tamamlayın. Yalnız eksik collateral tutarı işlem değeri olarak gönderilir.</p>
        </div>
        <button class="btn-primary w-full justify-center" :disabled="processing || delivery.courierFunded || !indexerReady" @click="fund">
          <PhCircleNotch v-if="processing" class="size-4 animate-spin" />
          {{ delivery.courierFunded ? 'Kurye payı fonlandı' : 'Kurye Payını Fonla' }}
        </button>
      </section>

      <section v-else-if="delivery.chainState === 'ReadyForPickup'" class="card space-y-4 rounded-xl bg-white p-5">
        <div>
          <h2 class="font-semibold text-stone-900">Müşteri kabulünü doğrula</h2>
          <p class="mt-1 text-xs leading-relaxed text-stone-500">Müşterinin kısa ömürlü EIP-712 kabul paketini yapıştırın. Paket URL’ye veya kalıcı depolamaya yazılmaz.</p>
        </div>
        <AcceptanceQrScanner @scanned="acceptancePackage = $event" />
        <textarea v-model.trim="acceptancePackage" rows="6" class="input resize-none font-mono text-[10px]" placeholder="İmzalı kabul paketi JSON" />
        <button class="btn-primary w-full justify-center" :disabled="processing || !acceptancePackage || !indexerReady" @click="confirmPickup">
          <PhCircleNotch v-if="processing" class="size-4 animate-spin" />
          <PhPackage v-else class="size-4" weight="bold" />
          Paketi Teslim Aldım
        </button>
      </section>

      <section v-else-if="delivery.chainState === 'InTransit'" class="card space-y-4 rounded-xl bg-white p-5">
        <div>
          <h2 class="font-semibold text-stone-900">Teslim kanıtı</h2>
          <p class="mt-1 text-xs leading-relaxed text-stone-500">Alıcıdan aldığınız kod backend’de doğrulanır. Ham OTP hiçbir zaman kontrata gönderilmez.</p>
        </div>
        <input v-model.trim="deliveryCode" type="password" autocomplete="one-time-code" maxlength="64" class="input text-center font-mono tracking-widest" placeholder="Teslim kodu" />
        <button class="btn-primary w-full justify-center" :disabled="processing || !deliveryCode || !indexerReady" @click="submitPod">
          <PhCircleNotch v-if="processing" class="size-4 animate-spin" />
          <PhCheckCircle v-else class="size-4" weight="fill" />
          Teslim Kanıtını Gönder
        </button>
      </section>

      <section v-else-if="delivery.chainState === 'ReturnRequired'" class="card space-y-4 rounded-xl bg-white p-5">
        <div>
          <h2 class="font-semibold text-stone-900">Müşterinin iade kabulünü doğrula</h2>
          <p class="mt-1 text-xs leading-relaxed text-stone-500">Paketi müşteriye iade ettiğinizde imzalı iade kabul paketini okutun veya yapıştırın.</p>
        </div>
        <AcceptanceQrScanner @scanned="acceptancePackage = $event" />
        <textarea v-model.trim="acceptancePackage" rows="6" class="input resize-none font-mono text-[10px]" placeholder="İmzalı iade kabul paketi JSON" />
        <button class="btn-primary w-full justify-center" :disabled="processing || !acceptancePackage || !indexerReady" @click="confirmReturn">
          <PhCircleNotch v-if="processing" class="size-4 animate-spin" />
          <PhPackage v-else class="size-4" weight="bold" />
          İadeyi Teslim Ettim
        </button>
      </section>

      <div v-else-if="delivery.chainState === 'DeliveredPending'" class="page-notice">
        Teslim kanıtı kaydedildi. Müşteri onayı veya challenge süresinin dolması bekleniyor.
      </div>
      <div v-else-if="delivery.chainState === 'Completed'" class="rounded-xl border border-green-200 bg-green-50 p-4 text-sm font-semibold text-green-700">
        <PhCheckCircle class="mr-2 inline size-5" weight="fill" /> Teslimat tamamlandı.
      </div>
      <div v-else-if="delivery.chainState === 'Returned'" class="rounded-xl border border-stone-200 bg-stone-50 p-4 text-sm font-semibold text-stone-700">
        <PhCheckCircle class="mr-2 inline size-5" weight="fill" /> İade tamamlandı.
      </div>
      <div v-else class="flex gap-2 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-700">
        <PhWarning class="mt-0.5 size-4 shrink-0" weight="fill" /> Bu zincir durumunda kurye aksiyonu yok.
      </div>

      <p v-if="!indexerReady" class="rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-700">
        Finalized indexer durumu {{ delivery.indexing.status }}. State-changing işlem projection hazır olana kadar kapalıdır.
      </p>

      <p v-if="message" class="rounded-lg border border-green-200 bg-green-50 px-3 py-2 text-sm text-green-700">{{ message }}</p>
      <p v-if="error" class="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">{{ error }}</p>
    </div>
  </div>
</template>
