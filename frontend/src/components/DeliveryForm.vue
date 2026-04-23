<script setup lang="ts">
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { PhCaretRight as ChevronRight, PhCaretLeft as ChevronLeft, PhCheck as Check } from '@phosphor-icons/vue'
import { useDeliveryStore } from '@/stores/useDeliveryStore'

const router = useRouter()
const store = useDeliveryStore()
const currentStep = ref(0)
const submitting = ref(false)
const done = ref(false)

const form = ref({ title: '', pickupAddress: '', dropoffAddress: '', weight: '', description: '', maxBudget: '', deadline: '' })

const steps = ['Adres Bilgileri', 'Paket Detayları', 'Bütçe & Süre', 'Önizleme']

const canNext = computed(() => {
  if (currentStep.value === 0) return form.value.pickupAddress && form.value.dropoffAddress && form.value.title
  if (currentStep.value === 1) return form.value.weight
  if (currentStep.value === 2) return form.value.maxBudget && form.value.deadline
  return true
})

async function submit() {
  submitting.value = true
  await new Promise(r => setTimeout(r, 1200))
  submitting.value = false
  done.value = true
  setTimeout(() => router.push('/deliveries'), 1800)
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
      <div class="mb-3 text-5xl">🎉</div>
      <h2 class="text-xl font-bold text-green-700">Teslimat Oluşturuldu!</h2>
      <p class="mt-2 text-stone-500">Ödemeniz kilitlendi. Yönlendiriliyorsunuz...</p>
    </div>

    <!-- Form card -->
    <div v-else v-auto-animate class="card rounded-xl bg-white p-7">
      <!-- Step 0 -->
      <div v-if="currentStep === 0" class="space-y-4">
        <h2 class="mb-4 font-semibold text-stone-900">📍 Adres Bilgileri</h2>
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
      </div>

      <!-- Step 1 -->
      <div v-else-if="currentStep === 1" class="space-y-4">
        <h2 class="mb-4 font-semibold text-stone-900">📦 Paket Detayları</h2>
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
        <h2 class="mb-4 font-semibold text-stone-900">💰 Bütçe & Süre</h2>
        <div>
          <label class="mb-1.5 block text-sm font-medium text-stone-700">Maks. Bütçe (MON)</label>
          <div class="relative">
            <input v-model="form.maxBudget" type="number" min="1" class="input pr-14" placeholder="Örn: 25" />
            <span class="absolute right-3.5 top-1/2 -translate-y-1/2 text-xs font-semibold text-stone-400">MON</span>
          </div>
          <p class="mt-1 text-xs text-stone-400">Bu tutar escrow'a kilitlenecek.</p>
        </div>
        <div>
          <label class="mb-1.5 block text-sm font-medium text-stone-700">Son Teslim Saati</label>
          <input v-model="form.deadline" type="time" class="input" />
        </div>
      </div>

      <!-- Step 3 Preview -->
      <div v-else class="space-y-4">
        <h2 class="mb-4 font-semibold text-stone-900">👁️ Önizleme</h2>
        <div class="space-y-2.5 rounded-lg border border-stone-100 bg-stone-50 p-4 text-sm">
          <div class="flex justify-between"><span class="text-stone-500">Başlık</span><span class="font-medium text-stone-900">{{ form.title }}</span></div>
          <div class="flex justify-between"><span class="text-stone-500">Nereden</span><span class="font-medium text-stone-900">{{ form.pickupAddress }}</span></div>
          <div class="flex justify-between"><span class="text-stone-500">Nereye</span><span class="font-medium text-stone-900">{{ form.dropoffAddress }}</span></div>
          <div class="flex justify-between"><span class="text-stone-500">Ağırlık</span><span class="font-medium text-stone-900">{{ form.weight }} kg</span></div>
          <div class="flex justify-between"><span class="text-stone-500">Bütçe</span><span class="font-semibold text-orange-600">{{ form.maxBudget }} MON</span></div>
          <div class="flex justify-between"><span class="text-stone-500">Son Saat</span><span class="font-medium text-stone-900">{{ form.deadline }}</span></div>
        </div>
        <div class="rounded-lg border border-orange-200 bg-orange-50 p-3 text-xs text-orange-700">
          ✅ Onayladıktan sonra <strong>{{ form.maxBudget }} MON</strong> akıllı sözleşmeye kilitlenecek
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
    </div>
  </div>
</template>
