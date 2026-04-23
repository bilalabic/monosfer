<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { useWalletStore } from '@/stores/useWalletStore'
import { useDeliveryStore } from '@/stores/useDeliveryStore'
import {
  PhUser, PhPackage, PhClockCounterClockwise, PhPhone, PhEnvelopeSimple,
  PhStar, PhTruck, PhMapPin, PhCheckCircle, PhClock,
  PhShieldCheck, PhHandshake, PhBell
} from '@phosphor-icons/vue'
import DeliveryCard from '@/components/DeliveryCard.vue'

const wallet = useWalletStore()
const deliveryStore = useDeliveryStore()

const activeTab = ref<'tracking' | 'past' | 'ratings' | 'settings'>('tracking')

const editPhone = ref(wallet.userProfile.phone)
const editName = ref(wallet.userProfile.name)
const savedMsg = ref('')
const saveError = ref('')
const savingProfile = ref(false)

watch(
  () => [wallet.userProfile.name, wallet.userProfile.phone],
  ([name, phone]) => {
    editName.value = name
    editPhone.value = phone
  },
  { immediate: true },
)

async function saveSettings() {
  savedMsg.value = ''
  saveError.value = ''
  savingProfile.value = true
  try {
    await wallet.updateProfile({ phone: editPhone.value, name: editName.value })
    savedMsg.value = 'Ayarlar kaydedildi!'
    setTimeout(() => savedMsg.value = '', 3000)
  } catch (error) {
    saveError.value = error instanceof Error ? error.message : 'Profil kaydedilemedi'
  } finally {
    savingProfile.value = false
  }
}

const activeDelivery = computed(() => deliveryStore.deliveries.find(d => d.status === 'in_progress'))
const pastDeliveries = computed(() => deliveryStore.deliveries.filter(d => d.status === 'completed'))

const roleConfig: Record<string, { label: string; color: string; icon: any }> = {
  sender:    { label: 'Gönderici', color: 'bg-blue-100 text-blue-700', icon: PhUser },
  courier:   { label: 'Kurye',     color: 'bg-orange-100 text-orange-700', icon: PhTruck },
  recipient: { label: 'Alıcı',     color: 'bg-green-100 text-green-700', icon: PhBell },
  system:    { label: 'Sistem',    color: 'bg-stone-100 text-stone-600', icon: PhShieldCheck },
}

const profileRoleLabel = computed(() => {
  if (wallet.userProfile.role === 'courier') return 'Kurye'
  if (wallet.userProfile.role === 'both') return 'Müşteri + Kurye'
  return 'Müşteri'
})

</script>

<template>
  <div class="mx-auto max-w-6xl px-5 py-10 sm:px-8">
    <!-- Header -->
    <div class="mb-8 flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
      <div>
        <h1 class="text-2xl font-bold text-stone-900 sm:text-3xl">Kullanıcı Paneli</h1>
        <p class="mt-1 text-stone-500">Hoş geldin, {{ wallet.userProfile.name || wallet.displayAddress() }}</p>
      </div>
    </div>

    <div class="flex flex-col gap-8 md:flex-row">
      <!-- Sidebar -->
      <div class="w-full md:w-64 shrink-0">
        <nav class="flex flex-row md:flex-col gap-2 overflow-x-auto pb-2 md:pb-0 hide-scrollbar">
          <button
            :class="['flex items-center gap-3 rounded-lg px-4 py-3 text-sm font-medium transition whitespace-nowrap', activeTab === 'tracking' ? 'bg-white text-orange-600 shadow-sm border border-stone-200' : 'text-stone-500 hover:bg-stone-50 hover:text-stone-900']"
            @click="activeTab = 'tracking'"
          >
            <PhMapPin class="size-5 shrink-0" :weight="activeTab === 'tracking' ? 'duotone' : 'regular'" />
            Kargom Nerede
          </button>
          <button
            :class="['flex items-center gap-3 rounded-lg px-4 py-3 text-sm font-medium transition whitespace-nowrap', activeTab === 'past' ? 'bg-white text-orange-600 shadow-sm border border-stone-200' : 'text-stone-500 hover:bg-stone-50 hover:text-stone-900']"
            @click="activeTab = 'past'"
          >
            <PhClockCounterClockwise class="size-5 shrink-0" :weight="activeTab === 'past' ? 'duotone' : 'regular'" />
            Geçmiş Teslimatlar
          </button>
          <button
            :class="['flex items-center gap-3 rounded-lg px-4 py-3 text-sm font-medium transition whitespace-nowrap', activeTab === 'ratings' ? 'bg-white text-orange-600 shadow-sm border border-stone-200' : 'text-stone-500 hover:bg-stone-50 hover:text-stone-900']"
            @click="activeTab = 'ratings'"
          >
            <PhStar class="size-5 shrink-0" :weight="activeTab === 'ratings' ? 'duotone' : 'regular'" />
            Puanlamalar
          </button>
          <button
            :class="['flex items-center gap-3 rounded-lg px-4 py-3 text-sm font-medium transition whitespace-nowrap', activeTab === 'settings' ? 'bg-white text-orange-600 shadow-sm border border-stone-200' : 'text-stone-500 hover:bg-stone-50 hover:text-stone-900']"
            @click="activeTab = 'settings'"
          >
            <PhUser class="size-5 shrink-0" :weight="activeTab === 'settings' ? 'duotone' : 'regular'" />
            Profil & Ayarlar
          </button>
        </nav>

        <!-- Sidebar stats (desktop only) -->
        <div class="mt-4 hidden md:block rounded-xl border border-stone-100 bg-white p-4 space-y-3">
          <div class="flex items-center justify-between text-sm">
            <span class="text-stone-500">Toplam Teslimat</span>
            <span class="font-semibold text-stone-900">{{ deliveryStore.deliveries.length }}</span>
          </div>
          <div class="flex items-center justify-between text-sm">
            <span class="text-stone-500">Tamamlanan</span>
            <span class="font-semibold text-green-600">{{ pastDeliveries.length }}</span>
          </div>
          <div class="flex items-center justify-between text-sm">
            <span class="text-stone-500">Puanım</span>
            <span class="flex items-center gap-1 font-semibold text-orange-600">
              <PhStar class="size-3.5" weight="fill" />
              {{ wallet.userProfile.rating }}
            </span>
          </div>
        </div>
      </div>

      <!-- Content -->
      <div class="flex-1 min-w-0" v-auto-animate>

        <!-- ─── Kargom Nerede ─── -->
        <div v-if="activeTab === 'tracking'" class="space-y-6">
          <div class="card bg-white p-6 rounded-2xl">
            <h2 class="mb-5 text-lg font-bold text-stone-900">Devam Eden Teslimatım</h2>

            <div v-if="activeDelivery">
              <!-- Delivery info -->
              <div class="mb-6 rounded-xl border border-stone-100 bg-stone-50 p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                <div>
                  <p class="text-sm font-semibold text-stone-900">{{ activeDelivery.title }}</p>
                  <p class="text-xs text-stone-500 mt-1 flex items-center gap-1">
                    <PhMapPin class="size-3.5" />
                    {{ activeDelivery.pickupAddress }}
                    <span class="mx-0.5">→</span>
                    {{ activeDelivery.dropoffAddress }}
                  </p>
                </div>
                <div class="flex items-center gap-2 rounded-lg bg-orange-50 border border-orange-200 px-3 py-1.5">
                  <PhClock class="size-4 text-orange-500" weight="duotone" />
                  <span class="text-xs font-medium text-orange-700">Aktif</span>
                </div>
              </div>

              <!-- 3-rol timeline -->
              <div class="space-y-0">
                <!-- Rol grubu başlıkları -->
                <div class="mb-4 grid grid-cols-3 gap-2 text-center text-xs font-semibold">
                  <div class="rounded-lg bg-blue-50 py-1.5 text-blue-700">Gönderici</div>
                  <div class="rounded-lg bg-orange-50 py-1.5 text-orange-700">Kurye</div>
                  <div class="rounded-lg bg-green-50 py-1.5 text-green-700">Alıcı</div>
                </div>

                <!-- Timeline adımları -->
                <div v-for="(step, index) in activeDelivery.timeline" :key="step.step" class="flex items-start gap-3">
                  <div class="flex flex-col items-center">
                    <div
                      :class="[
                        'flex size-7 items-center justify-center rounded-full border-2 transition-all shrink-0',
                        step.completed
                          ? 'border-green-400 bg-green-400 text-white'
                          : 'border-stone-200 bg-white text-stone-400',
                      ]"
                    >
                      <PhCheckCircle v-if="step.completed" class="size-3.5" weight="fill" />
                      <component
                        v-else
                        :is="step.role ? roleConfig[step.role]?.icon || PhPackage : PhPackage"
                        class="size-3"
                        weight="bold"
                      />
                    </div>
                    <div
                      v-if="index < activeDelivery.timeline.length - 1"
                      :class="['mt-1 mb-1 w-0.5 h-6', step.completed ? 'bg-green-300' : 'bg-stone-200']"
                    />
                  </div>
                  <div class="flex-1 pb-4">
                    <div class="flex flex-wrap items-center gap-2">
                      <span
                        v-if="step.role"
                        :class="['inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-semibold', roleConfig[step.role]?.color]"
                      >
                        {{ roleConfig[step.role]?.label }}
                      </span>
                      <span :class="['text-sm font-medium', step.completed ? 'text-stone-900' : 'text-stone-400']">
                        {{ step.label }}
                      </span>
                      <span v-if="step.time" class="ml-auto text-xs text-stone-400">{{ step.time }}</span>
                      <span v-else-if="!step.completed" class="ml-auto text-xs text-stone-300">Bekliyor</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div v-else class="py-12 text-center">
              <PhPackage class="mx-auto mb-3 size-12 text-stone-300" weight="duotone" />
              <p class="text-stone-500 font-medium">Şu an aktif bir teslimatınız bulunmuyor.</p>
              <p class="mt-2 text-sm text-stone-400">Yeni teslimat başlatmak için üst menüdeki butonu kullanın.</p>
            </div>
          </div>
        </div>

        <!-- ─── Geçmiş Teslimatlar ─── -->
        <div v-else-if="activeTab === 'past'" class="space-y-6">
          <h2 class="text-lg font-bold text-stone-900">Geçmiş Teslimatlar</h2>
          <div v-if="pastDeliveries.length > 0" class="grid gap-4 sm:grid-cols-2">
            <div v-for="d in pastDeliveries" :key="d.id" class="relative">
              <DeliveryCard :delivery="d" />
              <div v-if="d.rating" class="absolute top-3 right-3 flex items-center gap-1 rounded-full bg-amber-50 border border-amber-200 px-2 py-0.5">
                <PhStar class="size-3 text-amber-500" weight="fill" />
                <span class="text-xs font-semibold text-amber-700">{{ d.rating }}</span>
              </div>
            </div>
          </div>
          <div v-else class="py-12 text-center rounded-2xl bg-white border border-stone-200">
            <PhClockCounterClockwise class="mx-auto mb-3 size-12 text-stone-300" weight="duotone" />
            <p class="text-stone-500 font-medium">Geçmiş teslimatınız bulunmuyor.</p>
          </div>
        </div>

        <!-- ─── Puanlamalar ─── -->
        <div v-else-if="activeTab === 'ratings'" class="space-y-6">
          <div class="card bg-white p-6 rounded-2xl">
            <h2 class="mb-5 text-lg font-bold text-stone-900">Puanlamalarım</h2>
            <div class="py-10 text-center">
              <PhStar class="mx-auto mb-3 size-12 text-stone-200" weight="duotone" />
              <p class="font-semibold text-stone-900">Henüz değerlendirme yok</p>
              <p class="mt-1 text-sm text-stone-400">Teslimatlar tamamlandıkça puanlamalar burada görünecek</p>
            </div>
          </div>
        </div>

        <!-- ─── Profil & Ayarlar ─── -->
        <div v-else-if="activeTab === 'settings'" class="space-y-6">
          <!-- Quick stats -->
          <div class="grid grid-cols-3 gap-3">
            <div class="card bg-white rounded-xl p-4 text-center">
              <p class="text-2xl font-bold text-stone-900">{{ deliveryStore.deliveries.length }}</p>
              <p class="text-xs text-stone-500 mt-1">Toplam Teslimat</p>
            </div>
            <div class="card bg-white rounded-xl p-4 text-center">
              <p class="text-2xl font-bold text-green-600">{{ pastDeliveries.length }}</p>
              <p class="text-xs text-stone-500 mt-1">Tamamlanan</p>
            </div>
            <div class="card bg-white rounded-xl p-4 text-center">
              <p class="text-2xl font-bold text-orange-500 flex items-center justify-center gap-1">
                <PhStar class="size-5" weight="fill" />
                {{ wallet.userProfile.rating }}
              </p>
              <p class="text-xs text-stone-500 mt-1">Puanım</p>
            </div>
          </div>

          <!-- Profile form -->
          <div class="card bg-white p-6 rounded-2xl">
            <h2 class="mb-5 text-lg font-bold text-stone-900">Profil Güncelle</h2>
            <form @submit.prevent="saveSettings" class="space-y-4 max-w-md">
              <div>
                <label class="mb-1.5 block text-sm font-medium text-stone-700">Ad Soyad</label>
                <div class="relative">
                  <PhUser class="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-stone-400" />
                  <input v-model="editName" type="text" class="input pl-10" placeholder="Adınız Soyadınız" />
                </div>
              </div>

              <div>
                <label class="mb-1.5 block text-sm font-medium text-stone-700">Telefon Numarası</label>
                <div class="relative">
                  <PhPhone class="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-stone-400" />
                  <input v-model="editPhone" type="tel" class="input pl-10" placeholder="Örn: 0555 123 4567" />
                </div>
              </div>

              <div>
                <label class="mb-1.5 block text-sm font-medium text-stone-700">E-posta (Salt Okunur)</label>
                <div class="relative">
                  <PhEnvelopeSimple class="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-stone-400" />
                  <input :value="wallet.userProfile.email" disabled type="email" class="input pl-10 opacity-60 cursor-not-allowed" />
                </div>
              </div>

              <div>
                <label class="mb-1.5 block text-sm font-medium text-stone-700">Hesap Türü</label>
                <div class="flex items-center gap-2 rounded-lg border border-stone-100 bg-stone-50 px-3 py-2.5">
                  <PhHandshake class="size-4 text-stone-400" />
                  <span class="text-sm text-stone-700 capitalize">
                    {{ profileRoleLabel }}
                  </span>
                </div>
              </div>

              <div class="pt-2">
                <button type="submit" class="btn-primary w-full justify-center" :disabled="savingProfile">
                  {{ savingProfile ? 'Kaydediliyor...' : 'Kaydet' }}
                </button>
              </div>
              <p v-if="savedMsg" class="text-sm text-green-600 text-center font-medium">{{ savedMsg }}</p>
              <p v-if="saveError" class="text-sm text-red-600 text-center font-medium">{{ saveError }}</p>
            </form>
          </div>

          <!-- Shortcuts -->
          <div class="grid grid-cols-2 gap-3">
            <button
              class="card bg-white rounded-xl p-4 text-left hover:border-orange-200 transition cursor-pointer border border-stone-100"
              @click="activeTab = 'past'"
            >
              <PhClockCounterClockwise class="size-6 text-stone-400 mb-2" weight="duotone" />
              <p class="text-sm font-semibold text-stone-900">Geçmiş Teslimatlar</p>
              <p class="text-xs text-stone-500 mt-0.5">{{ pastDeliveries.length }} teslimat</p>
            </button>
            <button
              class="card bg-white rounded-xl p-4 text-left hover:border-orange-200 transition cursor-pointer border border-stone-100"
              @click="activeTab = 'ratings'"
            >
              <PhStar class="size-6 text-amber-400 mb-2" weight="duotone" />
              <p class="text-sm font-semibold text-stone-900">Puanlamalar</p>
              <p class="text-xs text-stone-500 mt-0.5">Değerlendirmeler</p>
            </button>
          </div>
        </div>

      </div>
    </div>
  </div>
</template>
