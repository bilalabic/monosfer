<script setup lang="ts">
import { ref, computed } from 'vue'
import { PhCaretRight as ChevronRight, PhCaretLeft as ChevronLeft, PhCheck as Check, PhConfetti, PhMapPin, PhPackage, PhCurrencyDollar, PhEye, PhCheckCircle } from '@phosphor-icons/vue'
import { useDeliveryStore } from '@/stores/useDeliveryStore'
import type { RecipientType } from '@/stores/useDeliveryStore'

const router = useRouter()
const store = useDeliveryStore()
const currentStep = ref(0)
const submitting = ref(false)
const done = ref(false)
const submitError = ref('')

const form = ref({
  title: '',
  pickupAddress: '',
  dropoffAddress: '',
  recipientType: 'person' as RecipientType,
  recipientName: '',
  businessName: '',
  contactPerson: '',
  orderRef: '',
  department: '',
  recipientNote: '',
  recipientPhone: '',
  recipientWallet: '',
  deliveryCode: '',
  weight: '',
  description: '',
  maxBudget: '',
  deadline: '',
  date: '',
})

const steps = ['Adres Bilgileri', 'Paket Detayları', 'Bütçe & Süre', 'Önizleme']
const defaultRecipientType = { value: 'person' as RecipientType, label: 'Kişi', hint: 'Bireysel alıcı' }
const recipientTypes: { value: RecipientType; label: string; hint: string }[] = [
  defaultRecipientType,
  { value: 'business', label: 'Restoran / Mağaza', hint: 'Sipariş veya işletme' },
  { value: 'office', label: 'Ofis / Firma', hint: 'Resepsiyon, depo, kat' },
  { value: 'other', label: 'Diğer', hint: 'Serbest alıcı tanımı' },
]
const selectedRecipientType = computed(() => recipientTypes.find(t => t.value === form.value.recipientType) ?? defaultRecipientType)
const recipientReady = computed(() => {
  if (form.value.recipientType === 'business') return form.value.businessName && form.value.contactPerson
  if (form.value.recipientType === 'office') return form.value.businessName && form.value.contactPerson
  if (form.value.recipientType === 'other') return form.value.recipientNote
  return form.value.recipientName
})
const recipientPreviewName = computed(() => {
  if (form.value.recipientType === 'business' || form.value.recipientType === 'office') return form.value.businessName
  if (form.value.recipientType === 'other') return form.value.recipientNote
  return form.value.recipientName
})

const canNext = computed(() => {
  if (currentStep.value === 0) return form.value.pickupAddress && form.value.dropoffAddress && form.value.title && recipientReady.value && form.value.deliveryCode
  if (currentStep.value === 1) return form.value.weight
  if (currentStep.value === 2) return form.value.maxBudget && form.value.deadline && form.value.date
  return true
})

async function submit() {
  submitting.value = true
  submitError.value = ''
  try {
    await store.createDelivery({
      title: form.value.title,
      pickupAddress: form.value.pickupAddress,
      dropoffAddress: form.value.dropoffAddress,
      recipientType: form.value.recipientType,
      recipientName: form.value.recipientName,
      businessName: form.value.businessName,
      contactPerson: form.value.contactPerson,
      orderRef: form.value.orderRef,
      department: form.value.department,
      recipientNote: form.value.recipientNote,
      recipientPhone: form.value.recipientPhone,
      recipientWallet: form.value.recipientWallet,
      deliveryCode: form.value.deliveryCode,
      weight: form.value.weight,
      description: form.value.description,
      maxBudget: parseFloat(form.value.maxBudget),
      date: form.value.date,
      deadline: form.value.deadline,
    })
    done.value = true
    setTimeout(() => router.push('/deliveries'), 1800)
  } catch (e) {
    submitError.value = e instanceof Error ? e.message : 'Teslimat oluşturulamadı, tekrar deneyin.'
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-xl px-5 py-12 sm:px-8">
    <div class="mb-8">
      <p class="mb-1 text-xs font-semibold uppercase tracking-widest text-orange-500">Blockchain Güvenceli</p>
      <h1 class="text-2xl font-bold text-stone-900">Yeni Teslimat Oluştur</h1>
      <p class="mt-1 text-stone-500">Ödeme akıllı sözleşmeye kilitlenir, kuryeler teklif verir</p>
    </div>

    <!-- Step indicator -->
    <div class="mb-8 flex items-center">
      <div v-for="(step, index) in steps" :key="step" class="flex flex-1 items-center">
        <div class="flex flex-col items-center">
          <div :class="[
            'flex size-8 items-center justify-center rounded-full border-2 text-xs font-semibold transition-all',
            index < currentStep ? 'border-green-500 bg-green-500 text-white' : index === currentStep ? 'border-orange-500 bg-orange-50 text-orange-600' : 'border-stone-200 text-stone-400',
          ]">
            <Check v-if="index < currentStep" class="size-3.5" weight="bold" />
            <span v-else>{{ index + 1 }}</span>
          </div>
        </div>
        <div v-if="index < steps.length - 1" :class="['flex-1 h-0.5 mx-1.5', index < currentStep ? 'bg-green-400' : 'bg-stone-200']" />
      </div>
    </div>

    <!-- Success -->
    <div v-if="done" class="rounded-xl border border-green-200 bg-green-50 p-10 text-center">
      <PhConfetti class="mx-auto mb-3 size-12 text-green-500" weight="duotone" />
      <h2 class="text-xl font-bold text-green-700">Teslimat Oluşturuldu!</h2>
      <p class="mt-2 text-stone-500">İlan yayınlandı. Teklif seçince ödemeyi escrow'a kilitleyebilirsiniz.</p>
    </div>

    <!-- Form card -->
    <div v-else v-auto-animate class="card rounded-xl bg-white p-7">
      <!-- Step 0 -->
      <div v-if="currentStep === 0" class="space-y-4">
        <h2 class="mb-4 flex items-center gap-2 font-semibold text-stone-900">
          <PhMapPin class="size-5 text-orange-500" weight="duotone" /> Adres Bilgileri
        </h2>
        <div>
          <label class="mb-1.5 block text-sm font-medium text-stone-700">Başlık</label>
          <input v-model="form.title" class="input" placeholder="Örn: Elektronik ürün teslimatı" />
        </div>
        <div>
          <label class="mb-1.5 block text-sm font-medium text-stone-700">Nereden (Alış)</label>
          <input v-model="form.pickupAddress" class="input" placeholder="Örn: Kadıköy, İstanbul" />
        </div>
        <div>
          <label class="mb-1.5 block text-sm font-medium text-stone-700">Nereye (Teslim)</label>
          <input v-model="form.dropoffAddress" class="input" placeholder="Örn: Beşiktaş, İstanbul" />
        </div>

        <div>
          <label class="mb-2 block text-sm font-medium text-stone-700">Alıcı Tipi</label>
          <div class="grid gap-2 sm:grid-cols-2">
            <button
              v-for="type in recipientTypes"
              :key="type.value"
              type="button"
              :class="[
                'rounded-lg border px-3 py-2 text-left transition',
                form.recipientType === type.value ? 'border-orange-400 bg-orange-50 text-orange-700' : 'border-stone-200 bg-white text-stone-600 hover:bg-stone-50',
              ]"
              @click="form.recipientType = type.value"
            >
              <span class="block text-sm font-semibold">{{ type.label }}</span>
              <span class="block text-xs text-stone-400">{{ type.hint }}</span>
            </button>
          </div>
        </div>

        <template v-if="form.recipientType === 'person'">
          <div class="grid gap-4 sm:grid-cols-2">
            <div>
              <label class="mb-1.5 block text-sm font-medium text-stone-700">Alıcı Adı</label>
              <input v-model="form.recipientName" class="input" placeholder="Örn: Ayşe Yılmaz" />
            </div>
            <div>
              <label class="mb-1.5 block text-sm font-medium text-stone-700">Alıcı Telefonu</label>
              <input v-model="form.recipientPhone" class="input" placeholder="Opsiyonel" />
            </div>
          </div>
        </template>

        <template v-else-if="form.recipientType === 'business'">
          <div>
            <label class="mb-1.5 block text-sm font-medium text-stone-700">İşletme Adı</label>
            <input v-model="form.businessName" class="input" placeholder="Örn: Lezzet Lokantası" />
          </div>
          <div class="grid gap-4 sm:grid-cols-2">
            <div>
              <label class="mb-1.5 block text-sm font-medium text-stone-700">Yetkili Kişi</label>
              <input v-model="form.contactPerson" class="input" placeholder="Örn: Murat Usta" />
            </div>
            <div>
              <label class="mb-1.5 block text-sm font-medium text-stone-700">Sipariş No</label>
              <input v-model="form.orderRef" class="input" placeholder="Opsiyonel" />
            </div>
          </div>
          <div>
            <label class="mb-1.5 block text-sm font-medium text-stone-700">İşletme Telefonu</label>
            <input v-model="form.recipientPhone" class="input" placeholder="Opsiyonel" />
          </div>
        </template>

        <template v-else-if="form.recipientType === 'office'">
          <div>
            <label class="mb-1.5 block text-sm font-medium text-stone-700">Firma / Ofis Adı</label>
            <input v-model="form.businessName" class="input" placeholder="Örn: Monad Labs Türkiye" />
          </div>
          <div class="grid gap-4 sm:grid-cols-2">
            <div>
              <label class="mb-1.5 block text-sm font-medium text-stone-700">Yetkili Kişi</label>
              <input v-model="form.contactPerson" class="input" placeholder="Örn: Resepsiyon" />
            </div>
            <div>
              <label class="mb-1.5 block text-sm font-medium text-stone-700">Departman / Kat</label>
              <input v-model="form.department" class="input" placeholder="Opsiyonel" />
            </div>
          </div>
        </template>

        <template v-else>
          <div>
            <label class="mb-1.5 block text-sm font-medium text-stone-700">Alıcı Açıklaması</label>
            <input v-model="form.recipientNote" class="input" placeholder="Örn: Güvenlik kulübesi, danışma, etkinlik alanı" />
          </div>
          <div>
            <label class="mb-1.5 block text-sm font-medium text-stone-700">İletişim Telefonu</label>
            <input v-model="form.recipientPhone" class="input" placeholder="Opsiyonel" />
          </div>
        </template>

        <div class="grid gap-4 sm:grid-cols-2">
          <div>
            <label class="mb-1.5 block text-sm font-medium text-stone-700">Teslim Kodu</label>
            <input
              v-model.trim="form.deliveryCode"
              class="input uppercase tracking-widest"
              maxlength="12"
              placeholder="Örn: A12345"
            />
          </div>
        </div>
        <div class="grid gap-4 sm:grid-cols-2">
          <div>
            <label class="mb-1.5 block text-sm font-medium text-stone-700">Alıcı Cüzdanı</label>
            <input v-model="form.recipientWallet" class="input" placeholder="Opsiyonel" />
          </div>
        </div>
        <p class="text-xs leading-relaxed text-stone-500">
          Bu kodu sadece gerçek alıcıyla paylaşın. Kurye teslimat QR'ını gösterdiğinde alıcı bu kodla ödemeyi serbest bırakır.
        </p>
      </div>

      <!-- Step 1 -->
      <div v-else-if="currentStep === 1" class="space-y-4">
        <h2 class="mb-4 flex items-center gap-2 font-semibold text-stone-900">
          <PhPackage class="size-5 text-orange-500" weight="duotone" /> Paket Detayları
        </h2>
        <div>
          <label class="mb-1.5 block text-sm font-medium text-stone-700">Ağırlık (kg)</label>
          <input v-model="form.weight" type="number" step="0.1" min="0.1" class="input" placeholder="Örn: 2.5" />
        </div>
        <div>
          <label class="mb-1.5 block text-sm font-medium text-stone-700">Açıklama (opsiyonel)</label>
          <textarea v-model="form.description" rows="3" class="input resize-none" placeholder="Kırılgan, soğuk zincir vb." />
        </div>
      </div>

      <!-- Step 2 -->
      <div v-else-if="currentStep === 2" class="space-y-4">
        <h2 class="mb-4 flex items-center gap-2 font-semibold text-stone-900">
          <PhCurrencyDollar class="size-5 text-orange-500" weight="duotone" /> Bütçe & Süre
        </h2>
        <div>
          <label class="mb-1.5 block text-sm font-medium text-stone-700">Maks. Bütçe (MON)</label>
          <div class="relative">
            <input v-model="form.maxBudget" type="number" min="1" class="input pr-14" placeholder="Örn: 25" />
            <span class="absolute right-3.5 top-1/2 -translate-y-1/2 text-xs font-semibold text-stone-400">MON</span>
          </div>
          <p class="mt-1 text-xs text-stone-400">Bu tutar escrow'a kilitlenecek.</p>
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div>
            <label class="mb-1.5 block text-sm font-medium text-stone-700">Tarih</label>
            <input v-model="form.date" type="date" class="input" />
          </div>
          <div>
            <label class="mb-1.5 block text-sm font-medium text-stone-700">Son Teslim Saati</label>
            <input v-model="form.deadline" type="time" class="input" />
          </div>
        </div>
      </div>

      <!-- Step 3 Preview -->
      <div v-else class="space-y-4">
        <h2 class="mb-4 flex items-center gap-2 font-semibold text-stone-900">
          <PhEye class="size-5 text-orange-500" weight="duotone" /> Önizleme
        </h2>
        <div class="space-y-2.5 rounded-lg border border-stone-100 bg-stone-50 p-4 text-sm">
          <div class="flex justify-between"><span class="text-stone-500">Başlık</span><span class="font-medium text-stone-900">{{ form.title }}</span></div>
          <div class="flex justify-between"><span class="text-stone-500">Nereden</span><span class="font-medium text-stone-900">{{ form.pickupAddress }}</span></div>
          <div class="flex justify-between"><span class="text-stone-500">Nereye</span><span class="font-medium text-stone-900">{{ form.dropoffAddress }}</span></div>
          <div class="flex justify-between gap-4"><span class="text-stone-500">Alıcı Tipi</span><span class="text-right font-medium text-stone-900">{{ selectedRecipientType.label }}</span></div>
          <div class="flex justify-between gap-4"><span class="text-stone-500">Alıcı</span><span class="text-right font-medium text-stone-900">{{ recipientPreviewName }}</span></div>
          <div v-if="form.contactPerson" class="flex justify-between gap-4"><span class="text-stone-500">Yetkili</span><span class="text-right font-medium text-stone-900">{{ form.contactPerson }}</span></div>
          <div v-if="form.orderRef" class="flex justify-between gap-4"><span class="text-stone-500">Sipariş No</span><span class="text-right font-medium text-stone-900">{{ form.orderRef }}</span></div>
          <div v-if="form.department" class="flex justify-between gap-4"><span class="text-stone-500">Departman / Kat</span><span class="text-right font-medium text-stone-900">{{ form.department }}</span></div>
          <div class="flex justify-between gap-4"><span class="text-stone-500">Teslim Kodu</span><span class="font-mono font-semibold uppercase tracking-widest text-stone-900">{{ form.deliveryCode }}</span></div>
          <div class="flex justify-between"><span class="text-stone-500">Ağırlık</span><span class="font-medium text-stone-900">{{ form.weight }} kg</span></div>
          <div class="flex justify-between"><span class="text-stone-500">Bütçe</span><span class="font-semibold text-orange-600">{{ form.maxBudget }} MON</span></div>
          <div class="flex justify-between"><span class="text-stone-500">Son Teslim</span><span class="font-medium text-stone-900">{{ form.date }} - {{ form.deadline }}</span></div>
        </div>
        <div class="flex items-start gap-2 rounded-lg border border-orange-200 bg-orange-50 p-3 text-xs text-orange-700">
          <PhCheckCircle class="mt-0.5 size-4 shrink-0" weight="fill" />
          <span>Onayladıktan sonra <strong>{{ form.maxBudget }} MON</strong> escrow kaydına alınacak</span>
        </div>
      </div>

      <!-- Navigation -->
      <div class="mt-7 flex items-center justify-between">
        <button
          :disabled="currentStep === 0"
          class="btn-secondary disabled:opacity-30 disabled:cursor-not-allowed"
          @click="currentStep--"
        >
          <ChevronLeft class="size-4" weight="bold" /> Geri
        </button>
        <button
          v-if="currentStep < steps.length - 1"
          :disabled="!canNext"
          class="btn-primary disabled:opacity-40 disabled:cursor-not-allowed"
          @click="currentStep++"
        >
          İleri <ChevronRight class="size-4" weight="bold" />
        </button>
        <button
          v-else
          :disabled="submitting"
          class="btn-primary disabled:opacity-40"
          @click="submit"
        >
          {{ submitting ? 'İşleniyor...' : 'Teslimatı Yayınla' }}
        </button>
      </div>
      <p v-if="submitError" class="mt-4 rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-center text-xs text-red-700">{{ submitError }}</p>
    </div>
  </div>
</template>
