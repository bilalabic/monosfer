<script setup lang="ts">
definePageMeta({ requiresAuth: true })

import { computed, ref } from 'vue'
import { PhArrowLeft, PhCheckCircle, PhCircleNotch, PhCopy, PhPackage, PhSealCheck } from '@phosphor-icons/vue'
import { useDeliveryStore } from '@/stores/useDeliveryStore'
import { useWalletStore } from '@/stores/useWalletStore'
import { deliveryStateLabel } from '@/utils/delivery-state'
import AcceptanceQrCode from '@/components/AcceptanceQrCode.vue'

const route = useRoute()
const router = useRouter()
const deliveries = useDeliveryStore()
const wallet = useWalletStore()
const id = route.params.id as string

if (!deliveries.getDelivery(id)) await deliveries.fetchDelivery(id)

const delivery = computed(() => deliveries.getDelivery(id))
const isOwner = computed(() => delivery.value?.senderId === wallet.address.toLowerCase())
const isCourier = computed(() => delivery.value?.assignedCourierId === wallet.address.toLowerCase())
const indexerReady = computed(() => delivery.value?.indexing.status === 'ready')
const processing = ref(false)
const error = ref('')
const message = ref('')
const signedPackage = ref('')
const deliveryCode = ref('')
const signedDetails = computed(() => {
  if (!signedPackage.value) return null
  try {
    const value = JSON.parse(signedPackage.value) as { acceptance: Record<string, string>; expiresAt: string }
    return value
  } catch { return null }
})

async function createAcceptance(kind: 'pickup' | 'return') {
  if (!delivery.value || !isOwner.value) return
  processing.value = true
  error.value = ''
  message.value = ''
  signedPackage.value = ''
  try {
    signedPackage.value = await deliveries.issueAcceptance(delivery.value.id, kind)
    message.value = 'İmzalı paket yalnız bellekte tutuluyor. Süresi dolmadan kuryeye güvenli şekilde aktarın.'
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : 'Kabul paketi imzalanamadı'
  } finally {
    processing.value = false
  }
}

async function copyPackage() {
  await navigator.clipboard.writeText(signedPackage.value)
  message.value = 'İmzalı paket panoya kopyalandı. Mesajı yalnız atanmış kuryeyle paylaşın.'
}

async function submitPod() {
  if (!delivery.value || !isCourier.value || !deliveryCode.value.trim()) return
  processing.value = true
  error.value = ''
  try {
    await deliveries.completeDeliveryWithRecipientCode(delivery.value.id, deliveryCode.value.trim())
    deliveryCode.value = ''
    message.value = 'Teslim kanıtı zincire gönderildi. İtiraz penceresi açıldı.'
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : 'Teslim kanıtı gönderilemedi'
  } finally {
    processing.value = false
  }
}

async function finalizeDelivery() {
  if (!delivery.value || !isOwner.value) return
  processing.value = true
  error.value = ''
  try {
    await deliveries.completeDelivery(delivery.value.id)
    message.value = 'Teslimat finalized projection üzerinde tamamlandı.'
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : 'Teslimat tamamlanamadı'
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
    <div v-else class="space-y-5">
      <page-header compact eyebrow="Güvenle teslim et" :title="`Teslimat #${delivery.id}`" :description="`Teslimat durumu: ${deliveryStateLabel(delivery.chainState)}`" />

      <p v-if="!indexerReady" class="rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-700">
        Finalized indexer durumu {{ delivery.indexing.status }}. Kanıt işlemleri projection hazır olana kadar kapalıdır.
      </p>

      <section v-if="delivery.chainState === 'ReadyForPickup' && isOwner" class="card space-y-4 rounded-xl bg-white p-5">
        <div>
          <h2 class="font-semibold text-stone-900">Paket devir kabulünü imzala</h2>
          <p class="mt-1 text-xs leading-relaxed text-stone-500">Backend’in ürettiği EIP-712 metnini cüzdanla imzalayın. Backend veya uygulama sizin adınıza imza atmaz.</p>
        </div>
        <button class="btn-primary w-full justify-center" :disabled="processing || !indexerReady" @click="createAcceptance('pickup')">
          <PhCircleNotch v-if="processing" class="size-4 animate-spin" />
          <PhPackage v-else class="size-4" weight="bold" />
          Kabul Paketini İmzala
        </button>
        <div v-if="signedPackage" class="space-y-2">
          <div v-if="signedDetails" class="rounded-lg border border-stone-200 bg-stone-50 p-3 text-xs text-stone-600">
            <p><strong>Teslimat:</strong> #{{ signedDetails.acceptance.deliveryId }}</p>
            <p class="mt-1 break-all"><strong>Kurye:</strong> {{ signedDetails.acceptance.courier }}</p>
            <p class="mt-1 break-all"><strong>Aksiyon:</strong> {{ signedDetails.acceptance.action }}</p>
            <p class="mt-1"><strong>Geçerlilik:</strong> {{ new Date(signedDetails.expiresAt).toLocaleString('tr-TR') }}</p>
          </div>
          <AcceptanceQrCode :payload="signedPackage" />
          <textarea :value="signedPackage" readonly rows="5" class="input resize-none font-mono text-[10px]" aria-label="İmzalı pickup kabul paketi" />
          <button class="btn-secondary w-full justify-center" @click="copyPackage"><PhCopy class="size-4" /> Güvenli aktarım için kopyala</button>
          <p class="text-xs text-amber-700">Bu veri URL’ye, analitiğe veya kalıcı tarayıcı depolamasına yazılmaz.</p>
        </div>
      </section>

      <section v-else-if="delivery.chainState === 'ReadyForPickup' && isCourier" class="page-notice">
        Müşterinin imzaladığı kabul paketini kullanmak için kurye işlem ekranına geçin.
        <button class="mt-3 block font-semibold underline" @click="router.push(`/courier/receive/${delivery.id}`)">Kurye ekranını aç</button>
      </section>

      <section v-else-if="delivery.chainState === 'ReturnRequired' && isOwner" class="card space-y-4 rounded-xl bg-white p-5">
        <div>
          <h2 class="font-semibold text-stone-900">İade kabulünü imzala</h2>
          <p class="mt-1 text-xs leading-relaxed text-stone-500">Kuryenin paketi size iade ettiğini kabul eden EIP-712 metnini cüzdanla imzalayın.</p>
        </div>
        <button class="btn-primary w-full justify-center" :disabled="processing || !indexerReady" @click="createAcceptance('return')">
          <PhCircleNotch v-if="processing" class="size-4 animate-spin" />
          <PhPackage v-else class="size-4" weight="bold" />
          İade Kabul Paketini İmzala
        </button>
        <div v-if="signedPackage" class="space-y-2">
          <div v-if="signedDetails" class="rounded-lg border border-stone-200 bg-stone-50 p-3 text-xs text-stone-600">
            <p><strong>Teslimat:</strong> #{{ signedDetails.acceptance.deliveryId }}</p>
            <p class="mt-1 break-all"><strong>Kurye:</strong> {{ signedDetails.acceptance.courier }}</p>
            <p class="mt-1 break-all"><strong>Aksiyon:</strong> {{ signedDetails.acceptance.action }}</p>
            <p class="mt-1"><strong>Geçerlilik:</strong> {{ new Date(signedDetails.expiresAt).toLocaleString('tr-TR') }}</p>
          </div>
          <AcceptanceQrCode :payload="signedPackage" />
          <textarea :value="signedPackage" readonly rows="5" class="input resize-none font-mono text-[10px]" aria-label="İmzalı iade kabul paketi" />
          <button class="btn-secondary w-full justify-center" @click="copyPackage"><PhCopy class="size-4" /> Güvenli aktarım için kopyala</button>
          <p class="text-xs text-amber-700">Bu veri URL’ye, analitiğe veya kalıcı tarayıcı depolamasına yazılmaz.</p>
        </div>
      </section>

      <section v-else-if="delivery.chainState === 'ReturnRequired' && isCourier" class="page-notice">
        Müşterinin imzaladığı iade kabul paketini kullanmak için kurye işlem ekranına geçin.
        <button class="mt-3 block font-semibold underline" @click="router.push(`/courier/receive/${delivery.id}`)">Kurye ekranını aç</button>
      </section>

      <section v-else-if="delivery.chainState === 'InTransit' && isCourier" class="card space-y-4 rounded-xl bg-white p-5">
        <div>
          <h2 class="font-semibold text-stone-900">Teslim kodunu doğrula</h2>
          <p class="mt-1 text-xs leading-relaxed text-stone-500">Ham kod zincire gönderilmez. Backend kodu doğrular ve kısa ömürlü PoD attestation döndürür.</p>
        </div>
        <input v-model.trim="deliveryCode" type="password" maxlength="64" autocomplete="one-time-code" class="input text-center font-mono tracking-widest" placeholder="Teslim kodu" />
        <button class="btn-primary w-full justify-center" :disabled="processing || !deliveryCode || !indexerReady" @click="submitPod">
          <PhCircleNotch v-if="processing" class="size-4 animate-spin" />
          <PhSealCheck v-else class="size-4" weight="bold" />
          Teslim Kanıtını Gönder
        </button>
      </section>

      <section v-else-if="delivery.chainState === 'DeliveredPending' && isOwner" class="card space-y-4 rounded-xl bg-white p-5">
        <p class="text-sm text-stone-600">Kurye teslim kanıtını gönderdi. Paketi aldıysanız itiraz penceresini beklemeden tamamlayabilirsiniz.</p>
        <button class="btn-primary w-full justify-center" :disabled="processing || !indexerReady" @click="finalizeDelivery">
          <PhCircleNotch v-if="processing" class="size-4 animate-spin" />
          <PhCheckCircle v-else class="size-4" weight="fill" />
          Teslimatı Tamamla
        </button>
      </section>

      <div v-else-if="delivery.chainState === 'Completed'" class="rounded-xl border border-green-200 bg-green-50 p-4 text-sm font-semibold text-green-700">
        <PhCheckCircle class="mr-2 inline size-5" weight="fill" /> Teslimat tamamlandı.
      </div>

      <div v-else-if="delivery.chainState === 'Returned'" class="rounded-xl border border-stone-200 bg-stone-50 p-4 text-sm font-semibold text-stone-700">
        <PhCheckCircle class="mr-2 inline size-5" weight="fill" /> Paket iade edildi.
      </div>

      <div v-else class="rounded-xl border border-stone-200 bg-stone-50 p-4 text-sm text-stone-600">
        Bu cüzdan ve zincir durumu için burada yapılabilecek bir işlem yok.
      </div>

      <p v-if="message" class="rounded-lg border border-green-200 bg-green-50 px-3 py-2 text-sm text-green-700">{{ message }}</p>
      <p v-if="error" class="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">{{ error }}</p>
    </div>
  </div>
</template>
