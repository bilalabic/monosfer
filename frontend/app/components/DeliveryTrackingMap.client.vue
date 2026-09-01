<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { deliveriesApi, type DeliveryCourierLocation } from '@/api/deliveries'
import { vehicleLabel } from '@/composables/useVehicleMeta'
import { timeAgo } from '@/composables/useTimeAgo'
import { createCourierMarkerIcon, createPointMarkerIcon } from '@/composables/useMapMarkerIcons'
import { createLeafletMap, destroyLeafletMap, CARTO_DARK_TILE_URL } from '@/composables/useLeafletMap'
import {
  PhMapPin,
  PhArrowClockwise,
  PhWarning,
  PhCheckCircle,
} from '@phosphor-icons/vue'

const props = defineProps<{ deliveryId: string }>()

const locationData = ref<DeliveryCourierLocation | null>(null)
const loading = ref(true)
const error = ref('')
const mapReady = ref(false)
let map: L.Map | null = null
let courierMarker: L.Marker | null = null
let pickupMarker: L.Marker | null = null
let dropoffMarker: L.Marker | null = null
let routeLine: L.Polyline | null = null
let refreshTimer: ReturnType<typeof setInterval> | null = null

function timeSince(dateStr: string | null) {
  return timeAgo(dateStr, { suffix: 'güncellendi' })
}

function createCourierIcon(data: DeliveryCourierLocation) {
  return createCourierMarkerIcon({ vehicleType: data.vehicleType, name: data.courierName, size: 44, pulse: true })
}

function createPickupIcon() {
  return createPointMarkerIcon({ emoji: '📦', color: '#22c55e' })
}

function createDropoffIcon() {
  return createPointMarkerIcon({ emoji: '🏠', color: '#ef4444' })
}

function updateMap(data: DeliveryCourierLocation) {
  if (!map) return

  // Kurye markeri
  if (!courierMarker) {
    courierMarker = L.marker([data.lat, data.lng], { icon: createCourierIcon(data), zIndexOffset: 1000 }).addTo(map)
  } else {
    courierMarker.setLatLng([data.lat, data.lng])
    courierMarker.setIcon(createCourierIcon(data))
  }

  // Alış noktası
  if (!pickupMarker) {
    pickupMarker = L.marker([data.pickup.lat, data.pickup.lng], { icon: createPickupIcon() })
      .addTo(map)
      .bindTooltip(`📦 Alış: ${data.pickup.address}`, { permanent: false })
  }

  // Teslimat noktası
  if (!dropoffMarker) {
    dropoffMarker = L.marker([data.dropoff.lat, data.dropoff.lng], { icon: createDropoffIcon() })
      .addTo(map)
      .bindTooltip(`🏠 Teslimat: ${data.dropoff.address}`, { permanent: false })
  }

  // Rota çizgisi
  if (routeLine) routeLine.remove()
  routeLine = L.polyline(
    [[data.pickup.lat, data.pickup.lng], [data.lat, data.lng], [data.dropoff.lat, data.dropoff.lng]],
    { color: '#f97316', weight: 3, opacity: 0.6, dashArray: '8, 6' },
  ).addTo(map)

  // İlk yüklemede haritayı 3 noktayı gösterecek şekilde fit et
  if (!mapReady.value) {
    const bounds = L.latLngBounds([
      [data.pickup.lat, data.pickup.lng],
      [data.lat, data.lng],
      [data.dropoff.lat, data.dropoff.lng],
    ])
    map.fitBounds(bounds, { padding: [40, 40] })
    mapReady.value = true
  }
}

async function loadLocation() {
  try {
    error.value = ''
    const data = await deliveriesApi.courierLocation(props.deliveryId)
    locationData.value = data
    if (map) updateMap(data)
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Konum alınamadı'
  } finally {
    loading.value = false
  }
}

function initMap() {
  const center: L.LatLngExpression = locationData.value
    ? [locationData.value.lat, locationData.value.lng]
    : [38.7205, 35.4826]

  map = createLeafletMap('delivery-tracking-map', {
    center,
    zoom: 14,
    attributionControl: false,
    tileUrl: CARTO_DARK_TILE_URL,
    tileOptions: { subdomains: 'abcd' },
  })

  if (locationData.value) updateMap(locationData.value)
}

onMounted(async () => {
  await loadLocation()
  initMap()
  // 20 saniyede bir konumu güncelle
  refreshTimer = setInterval(loadLocation, 20000)
})

onUnmounted(() => {
  if (refreshTimer) clearInterval(refreshTimer)
  map = destroyLeafletMap(map)
  courierMarker = null
  pickupMarker = null
  dropoffMarker = null
  routeLine = null
})
</script>

<template>
  <div class="overflow-hidden rounded-2xl border border-orange-200 bg-white shadow-sm">
    <!-- Başlık -->
    <div class="flex items-center justify-between border-b border-orange-100 bg-gradient-to-r from-orange-50 to-amber-50 px-5 py-3.5">
      <div class="flex items-center gap-2.5">
        <div class="flex size-8 items-center justify-center rounded-lg bg-orange-100">
          <PhMapPin class="size-4 text-orange-600" weight="duotone" />
        </div>
        <div>
          <p class="text-sm font-semibold text-stone-800">Kuryem Nerede?</p>
          <p class="text-xs text-stone-500">Canlı konum takibi</p>
        </div>
      </div>
      <button
        class="flex items-center gap-1.5 rounded-lg bg-white px-2.5 py-1.5 text-xs font-medium text-stone-600 shadow-sm ring-1 ring-stone-200 transition hover:bg-stone-50"
        :class="{ 'pointer-events-none opacity-60': loading }"
        @click="loadLocation"
      >
        <PhArrowClockwise class="size-3.5" :class="{ 'animate-spin': loading }" weight="bold" />
        Yenile
      </button>
    </div>

    <!-- Yükleniyor -->
    <div v-if="loading && !locationData" class="flex h-52 items-center justify-center bg-slate-950">
      <div class="flex flex-col items-center gap-3">
        <svg class="size-6 animate-spin text-orange-500" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/>
        </svg>
        <p class="text-sm text-slate-400">Kurye konumu alınıyor...</p>
      </div>
    </div>

    <!-- Hata -->
    <div v-else-if="error && !locationData" class="flex flex-col items-center gap-3 px-6 py-10 text-center">
      <PhWarning class="size-10 text-amber-400" weight="duotone" />
      <p class="font-medium text-stone-700">Konum alınamadı</p>
      <p class="text-sm text-stone-400">{{ error }}</p>
    </div>

    <!-- Harita -->
    <template v-else-if="locationData">
      <!-- Kurye Bilgi Satırı -->
      <div class="flex items-center gap-3 border-b border-stone-100 px-5 py-2.5">
        <div class="flex size-8 shrink-0 items-center justify-center rounded-full bg-orange-100 text-sm font-bold text-orange-700">
          {{ locationData.courierName.slice(0, 2).toUpperCase() }}
        </div>
        <div class="flex-1 min-w-0">
          <p class="truncate text-sm font-semibold text-stone-900">{{ locationData.courierName }}</p>
          <p class="text-xs text-stone-400">{{ vehicleLabel(locationData.vehicleType) }} • {{ timeSince(locationData.locationUpdatedAt) }}</p>
        </div>
        <div class="flex items-center gap-1.5 rounded-full bg-green-50 px-2.5 py-1 text-xs font-semibold text-green-700 ring-1 ring-green-200">
          <span class="size-1.5 animate-pulse rounded-full bg-green-500" />
          Yolda
        </div>
      </div>

      <!-- Harita Alanı -->
      <div id="delivery-tracking-map" class="h-64 w-full" />

      <!-- Rota Bilgisi -->
      <div class="grid grid-cols-2 divide-x divide-stone-100 border-t border-stone-100">
        <div class="flex items-center gap-2.5 px-4 py-3">
          <span class="flex size-6 shrink-0 items-center justify-center rounded-full bg-green-100 text-xs">📦</span>
          <div class="min-w-0">
            <p class="text-xs font-semibold text-stone-500">Alış</p>
            <p class="truncate text-xs font-medium text-stone-800">{{ locationData.pickup.address }}</p>
          </div>
        </div>
        <div class="flex items-center gap-2.5 px-4 py-3">
          <span class="flex size-6 shrink-0 items-center justify-center rounded-full bg-red-100 text-xs">🏠</span>
          <div class="min-w-0">
            <p class="text-xs font-semibold text-stone-500">Teslimat</p>
            <p class="truncate text-xs font-medium text-stone-800">{{ locationData.dropoff.address }}</p>
          </div>
        </div>
      </div>
    </template>

    <!-- Tamamlandı durumu (Delivered) -->
    <div v-if="locationData?.deliveryStatus === 'Delivered'" class="border-t border-green-100 bg-green-50 px-5 py-3">
      <div class="flex items-center gap-2 text-green-700">
        <PhCheckCircle class="size-4" weight="duotone" />
        <p class="text-sm font-semibold">Kargo teslim edildi!</p>
      </div>
    </div>
  </div>
</template>
