<script setup lang="ts">
import { computed, onMounted, ref, watchEffect } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { PhArrowLeft, PhCheckCircle, PhCircleNotch, PhPackage, PhSealCheck, PhStar } from '@phosphor-icons/vue'
import { useDeliveryStore } from '@/stores/useDeliveryStore'
import { useWalletStore } from '@/stores/useWalletStore'
import TokenAmount from '@/components/TokenAmount.vue'

const route = useRoute()
const router = useRouter()
const deliveryStore = useDeliveryStore()
const wallet = useWalletStore()

const delivery = computed(() => deliveryStore.getDelivery(route.params.id as string))
const mode = computed(() => route.query.step === 'delivery' ? 'delivery' : 'pickup')
const selectedBid = computed(() => delivery.value?.bids.find(bid => bid.id === delivery.value?.selectedBidId))
const isOwner = computed(() =>
  !!wallet.address &&
  !!delivery.value?.senderId &&
  wallet.address.toLowerCase() === delivery.value.senderId.toLowerCase()
)
const isAssignedCourier = computed(() =>
  !!wallet.address &&
  !!delivery.value?.assignedCourierId &&
  wallet.address.toLowerCase() === delivery.value.assignedCourierId.toLowerCase()
)
const canConfirmPickup = computed(() => isOwner.value || isAssignedCourier.value)
const isRecipientFlow = computed(() => mode.value === 'delivery' && !isOwner.value)
const canRate = computed(() => delivery.value?.status === 'completed' && isOwner.value && !delivery.value?.isRated)

const processing = ref(false)
const errorMsg = ref('')
const deliveryCode = ref('')
const ratingValue = ref(5)
const ratingComment = ref('')
const ratingSaving = ref(false)
const ratingMessage = ref('')

onMounted(() => {
  if (deliveryStore.deliveries.length === 0) deliveryStore.loadDeliveries()
})

watchEffect(() => {
  if (delivery.value && mode.value === 'pickup' && !canConfirmPickup.value) router.replace('/deliveries')
})

async function confirm() {
  if (!delivery.value || processing.value) return
  processing.value = true
  errorMsg.value = ''
  try {
    if (mode.value === 'pickup') {
      await deliveryStore.confirmPickup(delivery.value.id)
    } else if (isRecipientFlow.value) {
      await deliveryStore.completeDeliveryWithRecipientCode(delivery.value.id, deliveryCode.value)
    } else {
      await deliveryStore.completeDelivery(delivery.value.id)
    }
  } catch (error) {
    errorMsg.value = error instanceof Error ? error.message : 'Onay kaydedilemedi'
  } finally {
    processing.value = false
  }
}

async function submitRating() {
  if (!delivery.value || ratingSaving.value) return
  ratingSaving.value = true
  errorMsg.value = ''
  ratingMessage.value = ''
  try {
    await deliveryStore.rateDelivery(delivery.value.id, ratingValue.value, ratingComment.value)
    ratingMessage.value = 'Kurye puanı kaydedildi.'
  } catch (error) {
    errorMsg.value = error instanceof Error ? error.message : 'Puan kaydedilemedi'
  } finally {
    ratingSaving.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-lg px-5 py-10 sm:px-8">
    <button class="mb-6 flex items-center gap-1.5 text-sm text-stone-500 transition hover:text-stone-900" @click="router.back()">
      <PhArrowLeft class="size-4" weight="bold" /> Geri
    </button>

    <div v-if="!delivery || !selectedBid" class="py-20 text-center text-stone-500">
      Onaylanacak teslimat bulunamadı.
    </div>

    <div v-else class="space-y-5">
      <div>
        <p class="mb-1 text-xs font-semibold uppercase tracking-widest text-orange-500">QR Onayı</p>
        <h1 class="text-2xl font-bold text-stone-900">
          {{ mode === 'pickup' ? 'Paket Teslim Onayı' : 'Teslimat ve Ödeme Onayı' }}
        </h1>
        <p class="mt-1 text-sm text-stone-500">
          {{ mode === 'pickup'
            ? isAssignedCourier ? 'Göndericideki QR kodu okuttuysanız paketi teslim aldığınızı onaylayın.' : 'Paketi kuryeye teslim ettiyseniz bu adımı onaylayın.'
            : isRecipientFlow ? 'Paket elinizdeyse göndericinin size verdiği teslim kodunu girin. Kod doğruysa ödeme kuryeye serbest bırakılır.' : 'Paket ulaştıysa teslimatı tamamlayıp escrow ödemesini serbest bırakın.' }}
        </p>
      </div>

      <div class="card rounded-xl bg-white p-5">
        <p class="mb-2 text-sm font-semibold text-stone-900">{{ delivery.title }}</p>
        <p class="text-xs text-stone-500">{{ delivery.pickupAddress }} → {{ delivery.dropoffAddress }}</p>
        <div class="mt-4 flex items-center justify-between rounded-lg border border-stone-100 bg-stone-50 p-3">
          <span class="text-sm text-stone-500">Kurye</span>
          <span class="text-sm font-semibold text-stone-900">{{ selectedBid.courierName }}</span>
        </div>
        <div v-if="delivery.recipientName" class="mt-2 flex items-center justify-between rounded-lg border border-stone-100 bg-stone-50 p-3">
          <span class="text-sm text-stone-500">Alıcı</span>
          <span class="text-sm font-semibold text-stone-900">{{ delivery.recipientName }}</span>
        </div>
        <div class="mt-2 flex items-center justify-between rounded-lg border border-orange-100 bg-orange-50 p-3">
          <span class="text-sm text-stone-500">Ödeme</span>
          <TokenAmount :amount="selectedBid.tokenAmount" size="sm" />
        </div>
      </div>

      <div v-if="delivery.status === 'completed'" class="rounded-xl border border-green-200 bg-green-50 p-4">
        <div class="flex items-center gap-2 text-sm font-semibold text-green-700">
          <PhCheckCircle class="size-5" weight="fill" />
          Teslimat tamamlandı, ödeme serbest bırakıldı.
        </div>
      </div>

      <div v-if="mode === 'delivery' && isRecipientFlow && delivery.status !== 'completed'" class="card rounded-xl bg-white p-5">
        <label class="mb-2 block text-sm font-semibold text-stone-900">Teslim Kodu</label>
        <input
          v-model.trim="deliveryCode"
          class="input text-center font-mono uppercase tracking-widest"
          maxlength="12"
          placeholder="Kodu girin"
        />
        <p class="mt-2 text-xs leading-relaxed text-stone-500">
          Bu kod QR içinde yazmaz; güvenlik için gönderici tarafından alıcıya ayrıca verilmelidir.
        </p>
      </div>

      <button
        v-if="delivery.status !== 'completed'"
        class="btn-primary w-full justify-center"
        :disabled="processing || (isRecipientFlow && !deliveryCode.trim())"
        @click="confirm"
      >
        <PhCircleNotch v-if="processing" class="size-4 animate-spin" weight="bold" />
        <PhPackage v-else-if="mode === 'pickup'" class="size-4" weight="bold" />
        <PhSealCheck v-else class="size-4" weight="bold" />
        {{ processing ? 'Kaydediliyor...' : mode === 'pickup' ? isAssignedCourier ? 'Paketi Teslim Aldım' : 'Paketi Teslim Ettim' : isRecipientFlow ? 'Teslim Aldım, Ödemeyi Serbest Bırak' : 'Teslimatı Onayla ve Ödemeyi Tamamla' }}
      </button>

      <div v-if="canRate" class="card rounded-xl bg-white p-5">
        <p class="text-sm font-semibold text-stone-900">{{ selectedBid.courierName }} için puan ver</p>
        <div class="mt-3 flex gap-1">
          <button
            v-for="star in 5"
            :key="star"
            type="button"
            class="rounded p-0.5 text-amber-400 transition hover:scale-110"
            @click="ratingValue = star"
          >
            <PhStar class="size-7" :weight="star <= ratingValue ? 'fill' : 'regular'" />
          </button>
        </div>
        <textarea
          v-model="ratingComment"
          rows="3"
          maxlength="500"
          class="input mt-3 min-h-20 resize-none"
          placeholder="Kısa yorum yazabilirsiniz"
        />
        <button class="btn-primary mt-3 w-full justify-center" :disabled="ratingSaving" @click="submitRating">
          {{ ratingSaving ? 'Kaydediliyor...' : 'Kuryeyi Puanla' }}
        </button>
        <p v-if="ratingMessage" class="mt-2 text-center text-xs font-medium text-green-600">{{ ratingMessage }}</p>
      </div>

      <p v-if="errorMsg" class="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-center text-xs text-red-700">{{ errorMsg }}</p>
    </div>
  </div>
</template>
