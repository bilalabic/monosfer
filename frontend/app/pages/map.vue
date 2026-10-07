<script setup lang="ts">
definePageMeta({ layout: 'full-screen' })

import { ref, onMounted, onUnmounted, computed } from 'vue'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { couriersApi, type CourierLocation } from '@/api/couriers'
import { vehicleIcon, vehicleLabel } from '@/composables/useVehicleMeta'
import { createCourierMarkerIcon } from '@/composables/useMapMarkerIcons'
import { timeAgo } from '@/composables/useTimeAgo'
import { createLeafletMap, destroyLeafletMap } from '@/composables/useLeafletMap'
import {
  PhMapPin,
  PhArrowClockwise,
  PhCircle,
  PhWarning,
  PhCaretUp,
} from '@phosphor-icons/vue'

const couriers = ref<CourierLocation[]>([])
const loading = ref(true)
const error = ref('')
const selectedCourier = ref<CourierLocation | null>(null)
const mapReady = ref(false)
const lastUpdated = ref<Date | null>(null)
const mobileListOpen = ref(false)

let map: L.Map | null = null
let markersLayer: L.LayerGroup | null = null
let refreshTimer: ReturnType<typeof setInterval> | null = null

const onlineCouriers = computed(() => couriers.value.filter(c => c.isOnline))
const offlineCouriers = computed(() => couriers.value.filter(c => !c.isOnline))

function formatTime(dateStr: string | null) {
  return timeAgo(dateStr, { unknownLabel: 'Bilinmiyor' })
}

async function loadCouriers() {
  try {
    loading.value = true
    error.value = ''
    const data = await couriersApi.locations()
    couriers.value = data
    lastUpdated.value = new Date()
    if (map && mapReady.value) {
      renderMarkers()
    }
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Kuryeler yüklenemedi'
  } finally {
    loading.value = false
  }
}

function renderMarkers() {
  if (!map || !markersLayer) return

  markersLayer.clearLayers()

  couriers.value.forEach((courier) => {
    const isSelected = selectedCourier.value?.id === courier.id
    const icon = createCourierMarkerIcon({
      vehicleType: courier.vehicleType,
      name: courier.name,
      size: isSelected ? 44 : 36,
      background: courier.isOnline ? '#22c55e' : '#94a3b8',
      ringColor: isSelected ? '#f97316' : (courier.isOnline ? '#16a34a' : '#64748b'),
      pulse: isSelected,
    })

    const marker = L.marker([courier.lat, courier.lng], { icon })
    marker.on('click', () => {
      selectedCourier.value = courier
      renderMarkers()
    })
    markersLayer!.addLayer(marker)
  })
}

function flyToSelected() {
  if (!map || !selectedCourier.value) return
  map.flyTo([selectedCourier.value.lat, selectedCourier.value.lng], 15, { duration: 1 })
}

function initMap() {
  map = createLeafletMap('courier-map', { center: [38.7205, 35.4826], zoom: 13 })

  markersLayer = L.layerGroup().addTo(map)
  mapReady.value = true

  if (couriers.value.length > 0) {
    renderMarkers()
  }

  map.on('click', (e: L.LeafletMouseEvent) => {
    if (!(e.originalEvent.target as HTMLElement).closest('.leaflet-marker-icon')) {
      selectedCourier.value = null
      renderMarkers()
    }
  })
}

onMounted(async () => {
  await loadCouriers()
  initMap()
  renderMarkers()

  // 30 saniyede bir yenile
  refreshTimer = setInterval(loadCouriers, 30000)
})

onUnmounted(() => {
  if (refreshTimer) clearInterval(refreshTimer)
  map = destroyLeafletMap(map)
})
</script>

<template>
  <div class="map-frame relative flex h-full overflow-hidden">
    <!-- Sol Panel / Mobilde alttan açılan panel -->
    <aside
      class="fixed inset-x-0 bottom-0 z-20 flex max-h-[75vh] flex-col overflow-hidden rounded-t-2xl border-t border-stone-200 bg-white shadow-2xl transition-transform duration-300 lg:static lg:z-10 lg:max-h-none lg:w-72 lg:shrink-0 lg:translate-y-0 lg:rounded-none lg:border-r lg:border-t-0 lg:shadow-none"
      :class="mobileListOpen ? 'translate-y-0' : 'translate-y-full lg:translate-y-0'"
    >
      <!-- Başlık -->
      <div class="border-b border-stone-100 px-5 py-4">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2.5">
            <div class="flex size-8 items-center justify-center rounded-lg bg-orange-100">
              <PhMapPin class="size-4 text-orange-600" weight="duotone" />
            </div>
            <div>
              <h1 class="text-sm font-semibold text-stone-900">Kurye Haritası</h1>
              <p class="text-xs text-stone-500">Teslimata özel takip</p>
            </div>
          </div>
          <div class="flex items-center gap-2">
            <button
              class="flex size-7 items-center justify-center rounded-lg border border-stone-200 bg-white text-stone-500 transition hover:bg-stone-50 hover:text-stone-900"
              :class="{ 'animate-spin': loading }"
              title="Yenile"
              aria-label="Yenile"
              @click="loadCouriers"
            >
              <PhArrowClockwise class="size-3.5" weight="bold" />
            </button>
            <button
              class="flex size-7 items-center justify-center rounded-lg border border-stone-200 bg-white text-stone-500 transition hover:bg-stone-50 hover:text-stone-900 lg:hidden"
              aria-label="Listeyi kapat"
              @click="mobileListOpen = false"
            >
              <PhCaretUp class="size-3.5 rotate-180" weight="bold" />
            </button>
          </div>
        </div>

        <!-- Stats -->
        <div class="mt-4 grid grid-cols-2 gap-2">
          <div class="rounded-lg border border-green-100 bg-green-50 px-3 py-2 text-center">
            <p class="text-lg font-bold text-green-600">{{ onlineCouriers.length }}</p>
            <p class="text-xs text-green-700/70">Çevrimiçi</p>
          </div>
          <div class="rounded-lg border border-stone-200 bg-stone-50 px-3 py-2 text-center">
            <p class="text-lg font-bold text-stone-600">{{ offlineCouriers.length }}</p>
            <p class="text-xs text-stone-500">Çevrimdışı</p>
          </div>
        </div>

        <p v-if="lastUpdated" class="mt-2 text-center text-xs text-stone-400">
          Son güncelleme: {{ lastUpdated.toLocaleTimeString('tr-TR') }}
        </p>
      </div>

      <!-- Hata -->
      <div v-if="error" class="mx-4 mt-4 flex items-center gap-2 rounded-lg border border-red-200 bg-red-50 px-3 py-2.5">
        <PhWarning class="size-4 shrink-0 text-red-500" weight="duotone" />
        <p class="text-xs text-red-600">{{ error }}</p>
      </div>

      <!-- Kurye Listesi -->
      <div class="flex-1 overflow-y-auto px-3 py-3">
        <div v-if="loading && couriers.length === 0" class="flex h-32 items-center justify-center">
          <svg class="size-5 animate-spin text-orange-500" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/>
          </svg>
        </div>

        <div v-else-if="couriers.length === 0" class="flex h-32 flex-col items-center justify-center gap-2 text-center">
          <PhMapPin class="size-8 text-stone-300" weight="duotone" />
          <p class="text-sm text-stone-400">Paylaşılan konum yok</p>
        </div>

        <div v-else class="flex flex-col gap-1.5">
          <!-- Çevrimiçi -->
          <p v-if="onlineCouriers.length > 0" class="mb-1 mt-1 px-1 text-xs font-semibold uppercase tracking-widest text-green-600">
            Aktif
          </p>
          <button
            v-for="courier in onlineCouriers"
            :key="courier.id"
            class="group flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left transition"
            :class="selectedCourier?.id === courier.id
              ? 'bg-orange-50 ring-1 ring-orange-200'
              : 'hover:bg-stone-50'"
            @click="selectedCourier = courier; flyToSelected(); mobileListOpen = false"
          >
            <div class="relative flex size-9 shrink-0 items-center justify-center rounded-full bg-stone-700 text-sm font-semibold text-white">
              {{ courier.avatar }}
              <span class="absolute -right-0.5 -top-0.5 size-3 rounded-full border-2 border-white bg-green-500" />
            </div>
            <div class="min-w-0 flex-1">
              <p class="truncate text-sm font-medium text-stone-900">{{ courier.name }}</p>
              <p class="mt-0.5 flex items-center gap-1 text-xs text-stone-500">
                <component :is="vehicleIcon(courier.vehicleType)" class="size-3" weight="bold" />
                {{ vehicleLabel(courier.vehicleType) }}
              </p>
            </div>
            <PhMapPin
              class="size-4 shrink-0 text-stone-300 transition group-hover:text-orange-500"
              :class="{ 'text-orange-500': selectedCourier?.id === courier.id }"
              weight="duotone"
            />
          </button>

          <!-- Çevrimdışı -->
          <p v-if="offlineCouriers.length > 0" class="mb-1 mt-3 px-1 text-xs font-semibold uppercase tracking-widest text-stone-400">
            Çevrimdışı
          </p>
          <button
            v-for="courier in offlineCouriers"
            :key="courier.id"
            class="group flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left opacity-60 transition"
            :class="selectedCourier?.id === courier.id
              ? 'bg-stone-100 opacity-100 ring-1 ring-stone-300'
              : 'hover:bg-stone-50 hover:opacity-80'"
            @click="selectedCourier = courier; flyToSelected(); mobileListOpen = false"
          >
            <div class="relative flex size-9 shrink-0 items-center justify-center rounded-full bg-stone-400 text-sm font-semibold text-white">
              {{ courier.avatar }}
              <span class="absolute -right-0.5 -top-0.5 size-3 rounded-full border-2 border-white bg-stone-400" />
            </div>
            <div class="min-w-0 flex-1">
              <p class="truncate text-sm font-medium text-stone-700">{{ courier.name }}</p>
              <p class="mt-0.5 text-xs text-stone-400">{{ vehicleLabel(courier.vehicleType) }}</p>
            </div>
          </button>
        </div>
      </div>
    </aside>

    <!-- Harita -->
    <div class="relative flex-1">
      <div id="courier-map" class="size-full" />

      <!-- Mobilde kurye listesini açan buton -->
      <button
        v-if="!mobileListOpen"
        class="absolute bottom-4 right-4 z-[900] flex items-center gap-2 rounded-full border border-stone-200 bg-white px-4 py-2.5 text-sm font-semibold text-stone-700 shadow-lg lg:hidden"
        @click="mobileListOpen = true"
      >
        <PhMapPin class="size-4 text-orange-500" weight="duotone" />
        Kuryeler ({{ couriers.length }})
        <PhCaretUp class="size-3.5 text-stone-400" weight="bold" />
      </button>

      <!-- Seçili Kurye Bilgi Kartı -->
      <Transition
        enter-active-class="transition-all duration-300"
        enter-from-class="opacity-0 translate-y-4"
        enter-to-class="opacity-100 translate-y-0"
        leave-active-class="transition-all duration-200"
        leave-from-class="opacity-100 translate-y-0"
        leave-to-class="opacity-0 translate-y-4"
      >
        <div
          v-if="selectedCourier"
          class="absolute bottom-6 left-1/2 z-[1000] w-[min(92vw,420px)] -translate-x-1/2"
        >
          <div class="flex items-center gap-4 rounded-2xl border border-stone-200 bg-white px-5 py-4 shadow-2xl">
            <div class="relative flex size-12 shrink-0 items-center justify-center rounded-xl bg-stone-700 text-lg font-bold text-white">
              {{ selectedCourier.avatar }}
              <span
                class="absolute -right-1 -top-1 size-3.5 rounded-full border-2 border-white"
                :class="selectedCourier.isOnline ? 'bg-green-500' : 'bg-stone-400'"
              />
            </div>
            <div class="min-w-0 flex-1">
              <p class="truncate font-semibold text-stone-900">{{ selectedCourier.name }}</p>
              <div class="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-stone-500">
                <span class="flex items-center gap-1">
                  <component :is="vehicleIcon(selectedCourier.vehicleType)" class="size-3.5" weight="bold" />
                  {{ vehicleLabel(selectedCourier.vehicleType) }}
                </span>
                <span class="flex items-center gap-1">
                  <PhCircle
                    class="size-2.5"
                    weight="fill"
                    :class="selectedCourier.isOnline ? 'text-green-500' : 'text-stone-400'"
                  />
                  {{ selectedCourier.isOnline ? 'Çevrimiçi' : 'Çevrimdışı' }}
                </span>
                <span>{{ formatTime(selectedCourier.locationUpdatedAt) }}</span>
              </div>
              <p class="mt-1 truncate font-mono text-xs text-stone-400">{{ selectedCourier.walletAddress.slice(0, 12) }}...</p>
            </div>
            <button
              class="rounded-lg p-1.5 text-stone-400 transition hover:bg-stone-100 hover:text-stone-700"
              aria-label="Kapat"
              @click="selectedCourier = null; renderMarkers()"
            >
              ✕
            </button>
          </div>
        </div>
      </Transition>

      <!-- Boş Durum Overlay -->
      <div
        v-if="!loading && couriers.length === 0"
        class="pointer-events-none absolute inset-0 z-[500] flex items-center justify-center"
      >
        <div class="max-w-sm rounded-2xl border border-stone-200 bg-white/95 px-8 py-6 text-center shadow-lg backdrop-blur-md">
          <PhMapPin class="mx-auto mb-2 size-10 text-stone-300" weight="duotone" />
          <p class="font-semibold text-stone-900">Canlı takip teslimat detayında</p>
          <p class="mt-1 text-sm text-stone-500">Aktif teslimatının detayını açarak kuryenin paylaştığı konumu takip edebilirsin.</p>
        </div>
      </div>
    </div>
  </div>
</template>
