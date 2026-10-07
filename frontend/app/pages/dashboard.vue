<script setup lang="ts">
definePageMeta({ requiresAuth: true })

import { ref, computed, onMounted, watch, type Component } from 'vue'
import { useWalletStore } from '@/stores/useWalletStore'
import { useDeliveryStore } from '@/stores/useDeliveryStore'
import { vehicleLabel, type VehicleType } from '@/composables/useVehicleMeta'
import type { UserRole } from '@/api/auth'
import {
  PhUser, PhPackage, PhClockCounterClockwise, PhPhone, PhEnvelopeSimple,
  PhStar, PhTruck, PhMapPin, PhCheckCircle, PhClock,
  PhShieldCheck, PhHandshake, PhBell
} from '@phosphor-icons/vue'
import DeliveryCard from '@/components/DeliveryCard.vue'

const wallet = useWalletStore()
const deliveryStore = useDeliveryStore()
const router = useRouter()

type TabKey = 'tracking' | 'incoming' | 'bids' | 'past' | 'ratings' | 'settings'

const activeTab = ref<TabKey>('tracking')

const editPhone = ref(wallet.userProfile.phone)
const editName = ref(wallet.userProfile.name)
const editRole = ref<UserRole>(wallet.userProfile.role)
const editVehicleType = ref<VehicleType | null>(wallet.userProfile.vehicleType)
const savedMsg = ref('')
const saveError = ref('')
const savingProfile = ref(false)
const approvingBidId = ref('')
const incomingActionError = ref('')
const incomingActionSuccess = ref('')

const vehicleTypeOptions: VehicleType[] = ['on_foot', 'bicycle', 'motorcycle', 'car']

watch(
  () => ({
    name: wallet.userProfile.name,
    phone: wallet.userProfile.phone,
    role: wallet.userProfile.role,
    vehicleType: wallet.userProfile.vehicleType,
  }),
  ({ name, phone, role, vehicleType }) => {
    editName.value = name
    editPhone.value = phone
    editRole.value = role
    editVehicleType.value = vehicleType
  },
  { immediate: true },
)

async function saveSettings() {
  savedMsg.value = ''
  saveError.value = ''
  savingProfile.value = true
  try {
    await wallet.updateProfile({
      displayName: editName.value,
      phone: editPhone.value,
      role: editRole.value,
      courierProfile: editRole.value === 'courier'
        ? { vehicleType: editVehicleType.value ?? 'on_foot' }
        : null,
    })
    savedMsg.value = 'Ayarlar kaydedildi!'
    setTimeout(() => savedMsg.value = '', 3000)
  } catch (error) {
    saveError.value = error instanceof Error ? error.message : 'Profil kaydedilemedi'
  } finally {
    savingProfile.value = false
  }
}

const activeDelivery = computed(() => deliveryStore.deliveries.find(d => d.status === 'in_progress'))
const pastDeliveries = computed(() => {
  const terminalStatuses = ['completed', 'returned', 'resolved', 'cancelled', 'expired']
  return deliveryStore.deliveries.filter(delivery => terminalStatuses.includes(delivery.status))
})
const myBidRows = computed(() => {
  const address = wallet.address.toLowerCase()
  if (!address) return []

  return deliveryStore.deliveries.flatMap(delivery =>
    delivery.bids
      .filter(bid => bid.courierId.toLowerCase() === address)
      .map(bid => ({
        bid,
        delivery,
        isSelected: delivery.selectedBidId === bid.id,
      })),
  )
})

const incomingOfferRows = computed(() => {
  const address = wallet.address.toLowerCase()
  if (!address) return []

  return deliveryStore.deliveries
    .filter(delivery => delivery.senderId?.toLowerCase() === address && delivery.status === 'open')
    .flatMap(delivery =>
      delivery.bids.map(bid => ({
        delivery,
        bid,
      })),
    )
})

const tabs = computed<{ key: TabKey; label: string; icon: Component; badge?: number }[]>(() => [
  { key: 'tracking', label: 'Kargom Nerede', icon: PhMapPin },
  { key: 'incoming', label: 'Gelen Teklifler', icon: PhBell, badge: incomingOfferRows.value.length || undefined },
  { key: 'bids', label: 'Tekliflerim', icon: PhHandshake, badge: myBidRows.value.length || undefined },
  { key: 'past', label: 'Geçmiş Teslimatlar', icon: PhClockCounterClockwise },
  { key: 'ratings', label: 'Puanlamalar', icon: PhStar },
  { key: 'settings', label: 'Profil & Ayarlar', icon: PhUser },
])

const sidebarStats = computed(() => [
  { label: 'Toplam Teslimat', value: deliveryStore.deliveries.length, class: 'text-stone-900' },
  { label: 'Tamamlanan', value: pastDeliveries.value.length, class: 'text-green-600' },
  { label: 'Gelen Teklifler', value: incomingOfferRows.value.length, class: 'text-orange-600' },
  { label: 'Tekliflerim', value: myBidRows.value.length, class: 'text-orange-600' },
])

const quickStats = computed<{ label: string; value: number | string; class: string; icon?: Component }[]>(() => [
  { label: 'Toplam Teslimat', value: deliveryStore.deliveries.length, class: 'text-stone-900' },
  { label: 'Tamamlanan', value: pastDeliveries.value.length, class: 'text-green-600' },
  { label: 'Puanım', value: wallet.userProfile.rating, class: 'text-orange-500', icon: PhStar },
])

const shortcuts = computed<{ key: TabKey; icon: Component; iconClass: string; label: string; count: string }[]>(() => [
  { key: 'past', icon: PhClockCounterClockwise, iconClass: 'text-stone-400', label: 'Geçmiş Teslimatlar', count: `${pastDeliveries.value.length} teslimat` },
  { key: 'incoming', icon: PhBell, iconClass: 'text-orange-400', label: 'Gelen Teklifler', count: `${incomingOfferRows.value.length} teklif` },
  { key: 'bids', icon: PhHandshake, iconClass: 'text-orange-400', label: 'Tekliflerim', count: `${myBidRows.value.length} teklif` },
  { key: 'ratings', icon: PhStar, iconClass: 'text-amber-400', label: 'Puanlamalar', count: 'Değerlendirmeler' },
])

const roleConfig: Record<string, { label: string; color: string; icon: Component }> = {
  sender:    { label: 'Gönderici', color: 'bg-blue-100 text-blue-700', icon: PhUser },
  courier:   { label: 'Kurye',     color: 'bg-orange-100 text-orange-700', icon: PhTruck },
  recipient: { label: 'Alıcı',     color: 'bg-green-100 text-green-700', icon: PhBell },
  system:    { label: 'Sistem',    color: 'bg-stone-100 text-stone-600', icon: PhShieldCheck },
}

const statusLabel: Record<string, string> = {
  open: 'Teklif bekliyor',
  in_progress: 'Devam ediyor',
  completed: 'Tamamlandı',
  disputed: 'İtirazda',
}

function formatDateTime(date: string) {
  return new Date(date).toLocaleString('tr-TR', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
}

async function approveIncomingBid(deliveryId: string, bidId: string) {
  incomingActionError.value = ''
  incomingActionSuccess.value = ''
  approvingBidId.value = bidId

  try {
    await deliveryStore.selectBid(deliveryId, bidId)
    incomingActionSuccess.value = 'Teklif onaylandı. Şimdi ödeme kilitleme adımına geçebilirsin.'
  } catch (error) {
    incomingActionError.value = error instanceof Error ? error.message : 'Teklif onaylanamadı'
  } finally {
    approvingBidId.value = ''
  }
}

onMounted(() => {
  if (deliveryStore.deliveries.length === 0) {
    deliveryStore.loadDeliveries()
  }
})

</script>

<template>
  <div class="page-shell">
    <!-- Header -->
    <page-header eyebrow="Her yolculuk seninle başlar" title="Kullanıcı Paneli" :description="`Hoş geldin, ${wallet.userProfile.name || wallet.displayAddress()}. Teslimatlarını ve tekliflerini buradan yönet.`">
      <nuxt-link to="/create" class="btn-primary justify-center"><PhPackage class="size-4" weight="duotone" />Teslimat oluştur</nuxt-link>
    </page-header>

    <p v-if="deliveryStore.error" class="mb-6 rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">{{ deliveryStore.error }}</p>

    <div class="flex flex-col gap-8 md:flex-row">
      <!-- Sidebar -->
      <div class="w-full md:w-64 shrink-0">
        <nav class="dashboard-nav flex flex-row md:flex-col gap-2 overflow-x-auto hide-scrollbar">
          <button
            v-for="tab in tabs"
            :key="tab.key"
            :class="['flex items-center gap-3 rounded-lg px-4 py-3 text-sm font-medium transition whitespace-nowrap', activeTab === tab.key ? 'bg-white text-orange-600 shadow-sm border border-stone-200' : 'text-stone-500 hover:bg-stone-50 hover:text-stone-900']"
            @click="activeTab = tab.key"
          >
            <component :is="tab.icon" class="size-5 shrink-0" :weight="activeTab === tab.key ? 'duotone' : 'regular'" />
            {{ tab.label }}
            <span v-if="tab.badge" class="ml-auto rounded-full bg-orange-100 px-2 py-0.5 text-[10px] font-bold text-orange-700">{{ tab.badge }}</span>
          </button>
        </nav>

        <!-- Sidebar stats (desktop only) -->
        <div class="mt-4 hidden md:block rounded-xl border border-stone-100 bg-white p-4 space-y-3">
          <div v-for="s in sidebarStats" :key="s.label" class="flex items-center justify-between text-sm">
            <span class="text-stone-500">{{ s.label }}</span>
            <span :class="['font-semibold', s.class]">{{ s.value }}</span>
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

        <!-- ─── Gelen Teklifler ─── -->
        <div v-else-if="activeTab === 'incoming'" class="space-y-6">
          <div class="card rounded-2xl bg-white p-6">
            <div class="mb-5 flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <h2 class="text-lg font-bold text-stone-900">Gelen Teklifler</h2>
                <p class="mt-1 text-sm text-stone-500">Sana ait açık teslimatlara gelen kurye tekliflerini onaylayabilirsin</p>
              </div>
              <span class="rounded-full border border-orange-200 bg-orange-50 px-3 py-1 text-xs font-semibold text-orange-700">
                {{ incomingOfferRows.length }} teklif
              </span>
            </div>

            <p v-if="incomingActionSuccess" class="mb-4 rounded-lg border border-green-200 bg-green-50 px-3 py-2 text-sm font-medium text-green-700">
              {{ incomingActionSuccess }}
            </p>
            <p v-if="incomingActionError" class="mb-4 rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm font-medium text-red-700">
              {{ incomingActionError }}
            </p>

            <div v-if="incomingOfferRows.length > 0" class="space-y-3">
              <div
                v-for="{ delivery, bid } in incomingOfferRows"
                :key="`${delivery.id}-${bid.id}`"
                class="rounded-xl border border-stone-200 bg-stone-50 p-4 transition hover:border-orange-200 hover:bg-white hover:shadow-sm"
              >
                <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                  <div class="min-w-0">
                    <div class="mb-2 flex flex-wrap items-center gap-2">
                      <span class="rounded-full bg-stone-200 px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wide text-stone-600">
                        Onay Bekliyor
                      </span>
                      <span class="text-xs text-stone-400">{{ statusLabel[delivery.status] }}</span>
                    </div>
                    <h3 class="font-semibold text-stone-900">{{ delivery.title }}</h3>
                    <p class="mt-1 line-clamp-1 text-xs text-stone-500">
                      {{ delivery.pickupAddress }} → {{ delivery.dropoffAddress }}
                    </p>
                    <p class="mt-2 text-xs text-stone-400">
                      Kurye: {{ bid.courierName }} · {{ formatDateTime(bid.createdAt) }} · Tahmini süre: {{ bid.estimatedTime }}
                    </p>
                  </div>

                  <div class="flex shrink-0 flex-col gap-2 sm:items-end">
                    <p class="text-lg font-bold text-stone-900">{{ bid.tokenAmount }} MON</p>
                    <div class="flex gap-2">
                      <button
                        class="rounded-lg border border-stone-200 bg-white px-3 py-2 text-xs font-medium text-stone-600 transition hover:bg-stone-100"
                        @click="router.push(`/delivery/${delivery.id}`)"
                      >
                        Detay
                      </button>
                      <button
                        class="rounded-lg border border-orange-200 bg-orange-50 px-3 py-2 text-xs font-medium text-orange-700 transition hover:bg-orange-100 disabled:cursor-not-allowed disabled:opacity-60"
                        :disabled="approvingBidId === bid.id"
                        @click="approveIncomingBid(delivery.id, bid.id)"
                      >
                        {{ approvingBidId === bid.id ? 'Onaylanıyor...' : 'Onayla' }}
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div v-else class="py-12 text-center">
              <PhBell class="mx-auto mb-3 size-12 text-stone-300" weight="duotone" />
              <p class="font-semibold text-stone-900">Onay bekleyen teklif yok</p>
              <p class="mt-1 text-sm text-stone-500">Sana ait açık teslimatlara teklif geldiğinde burada listelenecek.</p>
              <button class="btn-primary mt-4 justify-center" @click="router.push('/deliveries')">Teslimatlara Git</button>
            </div>
          </div>
        </div>

        <!-- ─── Tekliflerim ─── -->
        <div v-else-if="activeTab === 'bids'" class="space-y-6">
          <div class="card rounded-2xl bg-white p-6">
            <div class="mb-5 flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <h2 class="text-lg font-bold text-stone-900">Tekliflerim</h2>
                <p class="mt-1 text-sm text-stone-500">Kurye olarak verdiğin teklifler ve seçilme durumları</p>
              </div>
              <span class="rounded-full border border-orange-200 bg-orange-50 px-3 py-1 text-xs font-semibold text-orange-700">
                {{ myBidRows.length }} teklif
              </span>
            </div>

            <div v-if="myBidRows.length > 0" class="space-y-3">
              <div
                v-for="{ bid, delivery, isSelected } in myBidRows"
                :key="bid.id"
                class="rounded-xl border border-stone-200 bg-stone-50 p-4 transition hover:border-orange-200 hover:bg-white hover:shadow-sm"
              >
                <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                  <div class="min-w-0">
                    <div class="mb-2 flex flex-wrap items-center gap-2">
                      <span
                        :class="[
                          'rounded-full px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wide',
                          isSelected ? 'bg-green-100 text-green-700' : 'bg-stone-200 text-stone-600',
                        ]"
                      >
                        {{ isSelected ? 'Seçildi' : 'Beklemede' }}
                      </span>
                      <span class="text-xs text-stone-400">{{ statusLabel[delivery.status] }}</span>
                    </div>
                    <h3 class="font-semibold text-stone-900">{{ delivery.title }}</h3>
                    <p class="mt-1 line-clamp-1 text-xs text-stone-500">
                      {{ delivery.pickupAddress }} → {{ delivery.dropoffAddress }}
                    </p>
                    <p class="mt-2 text-xs text-stone-400">
                      {{ formatDateTime(bid.createdAt) }} · Tahmini süre: {{ bid.estimatedTime }}
                    </p>
                  </div>

                  <div class="flex shrink-0 flex-col gap-2 sm:items-end">
                    <p class="text-lg font-bold text-stone-900">{{ bid.tokenAmount }} MON</p>
                    <div class="flex gap-2">
                      <button
                        class="rounded-lg border border-stone-200 bg-white px-3 py-2 text-xs font-medium text-stone-600 transition hover:bg-stone-100"
                        @click="router.push(`/delivery/${delivery.id}`)"
                      >
                        Detay
                      </button>
                      <button
                        v-if="isSelected && delivery.status === 'in_progress'"
                        class="rounded-lg border border-green-200 bg-green-50 px-3 py-2 text-xs font-medium text-green-700 transition hover:bg-green-100"
                        @click="router.push(`/courier/receive/${delivery.id}`)"
                      >
                        QR Ekranı
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div v-else class="py-12 text-center">
              <PhHandshake class="mx-auto mb-3 size-12 text-stone-300" weight="duotone" />
              <p class="font-semibold text-stone-900">Henüz teklif vermedin</p>
              <p class="mt-1 text-sm text-stone-500">Açık teslimatlardan birine teklif verdiğinde burada görünecek.</p>
              <button class="btn-primary mt-4 justify-center" @click="router.push('/deliveries')">Teslimatlara Git</button>
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
            <div v-for="s in quickStats" :key="s.label" class="card bg-white rounded-xl p-4 text-center">
              <p :class="['text-2xl font-bold flex items-center justify-center gap-1', s.class]">
                <component :is="s.icon" v-if="s.icon" class="size-5" weight="fill" />
                {{ s.value }}
              </p>
              <p class="text-xs text-stone-500 mt-1">{{ s.label }}</p>
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
                <div class="relative">
                  <PhHandshake class="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-stone-400" />
                  <select v-model="editRole" class="input pl-10">
                    <option value="customer">Müşteri</option>
                    <option value="courier">Kurye</option>
                  </select>
                </div>
              </div>

              <div v-if="editRole === 'courier'">
                <label class="mb-1.5 block text-sm font-medium text-stone-700">Araç Türü</label>
                <div class="relative">
                  <PhTruck class="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-stone-400" />
                  <select v-model="editVehicleType" class="input pl-10">
                    <option v-for="type in vehicleTypeOptions" :key="type" :value="type">
                      {{ vehicleLabel(type) }}
                    </option>
                  </select>
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
              v-for="s in shortcuts"
              :key="s.key"
              class="card bg-white rounded-xl p-4 text-left hover:border-orange-200 transition cursor-pointer border border-stone-100"
              @click="activeTab = s.key"
            >
              <component :is="s.icon" :class="['size-6 mb-2', s.iconClass]" weight="duotone" />
              <p class="text-sm font-semibold text-stone-900">{{ s.label }}</p>
              <p class="text-xs text-stone-500 mt-0.5">{{ s.count }}</p>
            </button>
          </div>
        </div>

      </div>
    </div>
  </div>
</template>
