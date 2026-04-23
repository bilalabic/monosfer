<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch } from 'vue'
import { deliveriesApi, type DeliveryCourierLocation } from '@/api/deliveries'
import {
  PhMapPin,
  PhMotorcycle,
  PhBicycle,
  PhCar,
  PhPersonSimpleWalk,
  PhArrowClockwise,
  PhWarning,
  PhCheckCircle,
} from '@phosphor-icons/vue'

const props = defineProps<{ deliveryId: string }>()

const locationData = ref<DeliveryCourierLocation | null>(null)
const loading = ref(true)
const error = ref('')
const mapReady = ref(false)
let map: any = null
let courierMarker: any = null
let pickupMarker: any = null
let dropoffMarker: any = null
let routeLine: any = null
let refreshTimer: ReturnType<typeof setInterval> | null = null

function vehicleLabel(type: string) {
  const labels: Record<string, string> = {
    bicycle: 'Bisiklet',
    motorcycle: 'Motosiklet',
    car: 'Araç',
    on_foot: 'Yaya',
  }
  return labels[type] || type
}

function vehicleEmoji(type: string) {
  const emojis: Record<string, string> = {
    bicycle: '🚲',
    motorcycle: '🏍️',
    car: '🚗',
    on_foot: '🚶',
  }
  return emojis[type] || '🏍️'
}

function timeSince(dateStr: string | null) {
  if (!dateStr) return 'Az önce güncellendi'
  const d = new Date(dateStr)
  const diff = Math.floor((Date.now() - d.getTime()) / 60000)
  if (diff < 1) return 'Az önce güncellendi'
  if (diff < 60) return `${diff} dk önce güncellendi`
  return `${Math.floor(diff / 60)} sa önce güncellendi`
}

function createCourierIcon(data: DeliveryCourierLocation) {
  const L = (window as any).L
  return L.divIcon({
    html: `
      <div style="position:relative;">
        <div style="
          width:44px; height:44px;
          background: linear-gradient(135deg, #f97316, #ea580c);
          border: 3px solid #fff;
          border-radius: 50%;
          display:flex; align-items:center; justify-content:center;
          box-shadow: 0 4px 16px rgba(249,115,22,0.5);
          font-size:20px;
          animation: pulse-ring 1.5s ease-out infinite;
        ">${vehicleEmoji(data.vehicleType)}</div>
        <div style="
          position:absolute; bottom:-8px; left:50%; transform:translateX(-50%);
          font-size:11px; font-weight:700;
          background:#1e293b; color:#f97316;
          border-radius:6px; padding:2px 6px;
          white-space:nowrap;
          box-shadow:0 2px 6px rgba(0,0,0,0.4);
          border: 1px solid rgba(249,115,22,0.3);
        ">${data.courierName.split(' ')[0]}</div>
      </div>
    `,
    className: '',
    iconSize: [44, 58],
    iconAnchor: [22, 22],
    popupAnchor: [0, -30],
  })
}

function createPickupIcon() {
  const L = (window as any).L
  return L.divIcon({
    html: `
      <div style="
        width:32px; height:32px;
        background:#22c55e;
        border: 3px solid #fff;
        border-radius:50%;
        display:flex; align-items:center; justify-content:center;
        box-shadow: 0 3px 10px rgba(34,197,94,0.5);
        font-size:16px;
      ">📦</div>
    `,
    className: '',
    iconSize: [32, 32],
    iconAnchor: [16, 16],
  })
}

function createDropoffIcon() {
  const L = (window as any).L
  return L.divIcon({
    html: `
      <div style="
        width:32px; height:32px;
        background:#ef4444;
        border: 3px solid #fff;
        border-radius:50%;
        display:flex; align-items:center; justify-content:center;
        box-shadow: 0 3px 10px rgba(239,68,68,0.5);
        font-size:16px;
      ">🏠</div>
    `,
    className: '',
    iconSize: [32, 32],
    iconAnchor: [16, 16],
  })
}

function updateMap(data: DeliveryCourierLocation) {
  const L = (window as any).L
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
  } catch (e: any) {
    error.value = e.message || 'Konum alınamadı'
  } finally {
    loading.value = false
  }
}

function loadLeaflet(): Promise<void> {
  return new Promise((resolve) => {
    if ((window as any).L) { resolve(); return }

    const link = document.createElement('link')
    link.rel = 'stylesheet'
    link.href = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css'
    document.head.appendChild(link)

    const script = document.createElement('script')
    script.src = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js'
    script.onload = () => resolve()
    document.head.appendChild(script)
  })
}

function initMap() {
  const L = (window as any).L
  const center = locationData.value
    ? [locationData.value.lat, locationData.value.lng]
    : [38.7205, 35.4826]

  map = L.map('delivery-tracking-map', {
    center,
    zoom: 14,
    zoomControl: true,
    attributionControl: false,
  })

  L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
    subdomains: 'abcd',
    maxZoom: 19,
  }).addTo(map)

  if (locationData.value) updateMap(locationData.value)
}

onMounted(async () => {
  await loadLeaflet()
  await loadLocation()
  initMap()
  // 20 saniyede bir konumu güncelle
  refreshTimer = setInterval(loadLocation, 20000)
})

onUnmounted(() => {
  if (refreshTimer) clearInterval(refreshTimer)
  if (map) { map.remove(); map = null }
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
