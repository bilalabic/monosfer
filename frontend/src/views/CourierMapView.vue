<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { couriersApi, type CourierLocation } from '@/api/couriers'
import {
  PhMapPin,
  PhMotorcycle,
  PhBicycle,
  PhCar,
  PhPersonSimpleWalk,
  PhArrowClockwise,
  PhCircle,
  PhWarning,
} from '@phosphor-icons/vue'

const couriers = ref<CourierLocation[]>([])
const loading = ref(true)
const error = ref('')
const selectedCourier = ref<CourierLocation | null>(null)
const mapReady = ref(false)
const lastUpdated = ref<Date | null>(null)

// Leaflet map instance
let map: any = null
let markersLayer: any = null
let refreshTimer: ReturnType<typeof setInterval> | null = null

const onlineCouriers = computed(() => couriers.value.filter(c => c.isOnline))
const offlineCouriers = computed(() => couriers.value.filter(c => !c.isOnline))

function vehicleIcon(type: string) {
  const icons: Record<string, any> = {
    bicycle: PhBicycle,
    motorcycle: PhMotorcycle,
    car: PhCar,
    on_foot: PhPersonSimpleWalk,
  }
  return icons[type] || PhMotorcycle
}

function vehicleLabel(type: string) {
  const labels: Record<string, string> = {
    bicycle: 'Bisiklet',
    motorcycle: 'Motosiklet',
    car: 'Araç',
    on_foot: 'Yaya',
  }
  return labels[type] || type
}

function formatTime(dateStr: string | null) {
  if (!dateStr) return 'Bilinmiyor'
  const d = new Date(dateStr)
  const diff = Math.floor((Date.now() - d.getTime()) / 60000)
  if (diff < 1) return 'Az önce'
  if (diff < 60) return `${diff} dk önce`
  return `${Math.floor(diff / 60)} sa önce`
}

function createMarkerHtml(courier: CourierLocation, isSelected = false) {
  const color = courier.isOnline ? '#22c55e' : '#94a3b8'
  const border = isSelected ? '#f97316' : (courier.isOnline ? '#16a34a' : '#64748b')
  const size = isSelected ? 44 : 36
  const avatarSize = isSelected ? 28 : 22

  const vehicleEmoji: Record<string, string> = {
    bicycle: '🚲',
    motorcycle: '🏍️',
    car: '🚗',
    on_foot: '🚶',
  }
  const emoji = vehicleEmoji[courier.vehicleType] || '🏍️'

  return `
    <div style="
      width:${size}px; height:${size}px;
      background:${color};
      border: 3px solid ${border};
      border-radius: 50% 50% 50% 0;
      transform: rotate(-45deg);
      display:flex; align-items:center; justify-content:center;
      box-shadow: 0 4px 12px rgba(0,0,0,0.3);
      transition: all 0.2s;
      cursor: pointer;
    ">
      <div style="transform:rotate(45deg); font-size:${avatarSize * 0.6}px; color:white; font-weight:bold;">
        ${courier.avatar}
      </div>
    </div>
    <div style="
      position:absolute; bottom:-6px; left:50%; transform:translateX(-50%);
      font-size:10px; background:#1e293b; color:white; border-radius:4px; padding:1px 4px;
      white-space:nowrap; box-shadow:0 2px 4px rgba(0,0,0,0.2);
    ">
      ${emoji} ${courier.name.split(' ')[0]}
    </div>
  `
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

  couriers.value.forEach(courier => {
    const L = (window as any).L
    const icon = L.divIcon({
      html: `<div style="position:relative;">${createMarkerHtml(courier, selectedCourier.value?.id === courier.id)}</div>`,
      className: '',
      iconSize: [44, 50],
      iconAnchor: [22, 50],
      popupAnchor: [0, -50],
    })

    const marker = L.marker([courier.lat, courier.lng], { icon })
    marker.on('click', () => {
      selectedCourier.value = courier
      renderMarkers() // re-render to update selected state
    })
    markersLayer.addLayer(marker)
  })
}

function flyToSelected() {
  if (!map || !selectedCourier.value) return
  map.flyTo([selectedCourier.value.lat, selectedCourier.value.lng], 15, { duration: 1 })
}

function initMap() {
  const L = (window as any).L
  if (!L) return

  map = L.map('courier-map', {
    center: [38.7205, 35.4826],
    zoom: 13,
    zoomControl: true,
  })

  L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
    attribution: '&copy; OpenStreetMap &copy; CARTO',
    subdomains: 'abcd',
    maxZoom: 19,
  }).addTo(map)

  markersLayer = L.layerGroup().addTo(map)
  mapReady.value = true

  if (couriers.value.length > 0) {
    renderMarkers()
  }

  map.on('click', (e: any) => {
    if (!(e.originalEvent.target as HTMLElement).closest('.leaflet-marker-icon')) {
      selectedCourier.value = null
      renderMarkers()
    }
  })
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

onMounted(async () => {
  await loadLeaflet()
  await loadCouriers()
  initMap()
  renderMarkers()

  // 30 saniyede bir yenile
  refreshTimer = setInterval(loadCouriers, 30000)
})

onUnmounted(() => {
  if (refreshTimer) clearInterval(refreshTimer)
  if (map) { map.remove(); map = null }
})
</script>

<template>
  <div class="relative flex h-[calc(100vh-65px)] overflow-hidden bg-slate-950">

    <!-- Sol Panel -->
    <aside class="relative z-10 flex w-72 shrink-0 flex-col border-r border-slate-800 bg-slate-900/95 backdrop-blur-sm">
      <!-- Başlık -->
      <div class="border-b border-slate-800 px-5 py-4">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2.5">
            <div class="flex size-8 items-center justify-center rounded-lg bg-orange-500/20">
              <PhMapPin class="size-4 text-orange-400" weight="duotone" />
            </div>
            <div>
              <h1 class="text-sm font-semibold text-white">Kurye Haritası</h1>
              <p class="text-xs text-slate-400">Canlı Konum Takibi</p>
            </div>
          </div>
          <button
            class="flex size-7 items-center justify-center rounded-lg bg-slate-800 text-slate-400 transition hover:bg-slate-700 hover:text-white"
            :class="{ 'animate-spin': loading }"
            title="Yenile"
            @click="loadCouriers"
          >
            <PhArrowClockwise class="size-3.5" weight="bold" />
          </button>
        </div>

        <!-- Stats -->
        <div class="mt-4 grid grid-cols-2 gap-2">
          <div class="rounded-lg bg-green-500/10 px-3 py-2 text-center">
            <p class="text-lg font-bold text-green-400">{{ onlineCouriers.length }}</p>
            <p class="text-xs text-green-300/70">Çevrimiçi</p>
          </div>
          <div class="rounded-lg bg-slate-800 px-3 py-2 text-center">
            <p class="text-lg font-bold text-slate-300">{{ offlineCouriers.length }}</p>
            <p class="text-xs text-slate-500">Çevrimdışı</p>
          </div>
        </div>

        <p v-if="lastUpdated" class="mt-2 text-center text-xs text-slate-500">
          Son güncelleme: {{ lastUpdated.toLocaleTimeString('tr-TR') }}
        </p>
      </div>

      <!-- Hata -->
      <div v-if="error" class="mx-4 mt-4 flex items-center gap-2 rounded-lg border border-red-900 bg-red-950/50 px-3 py-2.5">
        <PhWarning class="size-4 shrink-0 text-red-400" weight="duotone" />
        <p class="text-xs text-red-300">{{ error }}</p>
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
          <PhMapPin class="size-8 text-slate-600" weight="duotone" />
          <p class="text-sm text-slate-500">Kayıtlı kurye bulunamadı</p>
        </div>

        <div v-else class="flex flex-col gap-1.5">
          <!-- Çevrimiçi -->
          <p v-if="onlineCouriers.length > 0" class="mb-1 mt-1 px-1 text-xs font-semibold uppercase tracking-widest text-green-500">
            Aktif
          </p>
          <button
            v-for="courier in onlineCouriers"
            :key="courier.id"
            class="group flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left transition"
            :class="selectedCourier?.id === courier.id
              ? 'bg-orange-500/20 ring-1 ring-orange-500/50'
              : 'hover:bg-slate-800'"
            @click="selectedCourier = courier; flyToSelected()"
          >
            <div class="relative flex size-9 shrink-0 items-center justify-center rounded-full bg-slate-700 text-sm font-semibold text-white">
              {{ courier.avatar }}
              <span class="absolute -right-0.5 -top-0.5 size-3 rounded-full border-2 border-slate-900 bg-green-500" />
            </div>
            <div class="min-w-0 flex-1">
              <p class="truncate text-sm font-medium text-white">{{ courier.name }}</p>
              <p class="mt-0.5 flex items-center gap-1 text-xs text-slate-400">
                <component :is="vehicleIcon(courier.vehicleType)" class="size-3" weight="bold" />
                {{ vehicleLabel(courier.vehicleType) }}
              </p>
            </div>
            <PhMapPin
              class="size-4 shrink-0 text-slate-500 transition group-hover:text-orange-400"
              :class="{ 'text-orange-400': selectedCourier?.id === courier.id }"
              weight="duotone"
            />
          </button>

          <!-- Çevrimdışı -->
          <p v-if="offlineCouriers.length > 0" class="mb-1 mt-3 px-1 text-xs font-semibold uppercase tracking-widest text-slate-500">
            Çevrimdışı
          </p>
          <button
            v-for="courier in offlineCouriers"
            :key="courier.id"
            class="group flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left opacity-60 transition"
            :class="selectedCourier?.id === courier.id
              ? 'bg-slate-700/50 ring-1 ring-slate-600 opacity-100'
              : 'hover:bg-slate-800 hover:opacity-80'"
            @click="selectedCourier = courier; flyToSelected()"
          >
            <div class="relative flex size-9 shrink-0 items-center justify-center rounded-full bg-slate-700 text-sm font-semibold text-white">
              {{ courier.avatar }}
              <span class="absolute -right-0.5 -top-0.5 size-3 rounded-full border-2 border-slate-900 bg-slate-500" />
            </div>
            <div class="min-w-0 flex-1">
              <p class="truncate text-sm font-medium text-slate-300">{{ courier.name }}</p>
              <p class="mt-0.5 text-xs text-slate-500">{{ vehicleLabel(courier.vehicleType) }}</p>
            </div>
          </button>
        </div>
      </div>
    </aside>

    <!-- Harita -->
    <div class="relative flex-1">
      <div id="courier-map" class="size-full" />

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
          class="absolute bottom-6 left-1/2 z-[1000] -translate-x-1/2"
        >
          <div class="flex items-center gap-4 rounded-2xl border border-white/10 bg-slate-900/95 px-5 py-4 shadow-2xl backdrop-blur-md">
            <div class="relative flex size-12 shrink-0 items-center justify-center rounded-xl bg-slate-700 text-lg font-bold text-white">
              {{ selectedCourier.avatar }}
              <span
                class="absolute -right-1 -top-1 size-3.5 rounded-full border-2 border-slate-900"
                :class="selectedCourier.isOnline ? 'bg-green-500' : 'bg-slate-500'"
              />
            </div>
            <div>
              <p class="font-semibold text-white">{{ selectedCourier.name }}</p>
              <div class="mt-1 flex items-center gap-3 text-xs text-slate-400">
                <span class="flex items-center gap-1">
                  <component :is="vehicleIcon(selectedCourier.vehicleType)" class="size-3.5" weight="bold" />
                  {{ vehicleLabel(selectedCourier.vehicleType) }}
                </span>
                <span class="flex items-center gap-1">
                  <PhCircle
                    class="size-2.5"
                    weight="fill"
                    :class="selectedCourier.isOnline ? 'text-green-400' : 'text-slate-500'"
                  />
                  {{ selectedCourier.isOnline ? 'Çevrimiçi' : 'Çevrimdışı' }}
                </span>
                <span>{{ formatTime(selectedCourier.locationUpdatedAt) }}</span>
              </div>
              <p class="mt-1 font-mono text-xs text-slate-500">{{ selectedCourier.walletAddress.slice(0, 12) }}...</p>
            </div>
            <button
              class="ml-2 rounded-lg p-1.5 text-slate-500 transition hover:bg-slate-800 hover:text-white"
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
        <div class="rounded-2xl border border-white/10 bg-slate-900/90 px-8 py-6 text-center backdrop-blur-md">
          <PhMapPin class="mx-auto mb-2 size-10 text-slate-500" weight="duotone" />
          <p class="font-semibold text-white">Kayıtlı Kurye Yok</p>
          <p class="mt-1 text-sm text-slate-400">Kuryeler kayıt olduğunda haritada görünecek</p>
        </div>
      </div>
    </div>
  </div>
</template>
