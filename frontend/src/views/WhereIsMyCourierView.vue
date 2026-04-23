<script setup lang="ts">
import { ref, onMounted, onUnmounted, computed } from 'vue'
import {
  PhMapPin,
  PhMotorcycle,
  PhBicycle,
  PhCar,
  PhPersonSimpleWalk,
  PhArrowClockwise,
  PhCircle,
  PhPackage,
  PhFlagCheckered,
  PhNavigationArrow,
  PhPath,
} from '@phosphor-icons/vue'

type VehicleType = 'bicycle' | 'motorcycle' | 'car' | 'on_foot'

interface FakeCourier {
  id: string
  name: string
  avatar: string
  vehicleType: VehicleType
  phone: string
  rating: number
  // Başlangıç ve bitiş konumları
  start: { lat: number; lng: number; label: string }
  end: { lat: number; lng: number; label: string }
  // 0..1 arası ilerleme
  progress: number
  // tur başına ilerleme (km/h etkisi)
  speed: number
  packageCode: string
}

// Kayseri merkez koordinatları
const KAYSERI_CENTER: [number, number] = [38.7312, 35.4787]

// Kayseri'nin gerçek semt ve noktalarından birkaç örnek rota
const INITIAL_COURIERS: FakeCourier[] = [
  {
    id: 'c-1',
    name: 'Ahmet Yıldız',
    avatar: 'AY',
    vehicleType: 'motorcycle',
    phone: '+90 532 111 22 33',
    rating: 4.8,
    start: { lat: 38.7372, lng: 35.4839, label: 'Cumhuriyet Meydanı' },
    end:   { lat: 38.6826, lng: 35.5565, label: 'Talas Mevlana Mah.' },
    progress: 0.32,
    speed: 0.0025,
    packageCode: 'DLV-7A93',
  },
  {
    id: 'c-2',
    name: 'Mehmet Demir',
    avatar: 'MD',
    vehicleType: 'car',
    phone: '+90 533 222 33 44',
    rating: 4.6,
    start: { lat: 38.7519, lng: 35.4066, label: 'Mimarsinan OSB' },
    end:   { lat: 38.7058, lng: 35.4955, label: 'Erciyes Üniversitesi' },
    progress: 0.58,
    speed: 0.0018,
    packageCode: 'DLV-2B17',
  },
  {
    id: 'c-3',
    name: 'Emine Kaya',
    avatar: 'EK',
    vehicleType: 'bicycle',
    phone: '+90 505 333 44 55',
    rating: 4.9,
    start: { lat: 38.7298, lng: 35.4954, label: 'Sivas Caddesi' },
    end:   { lat: 38.7213, lng: 35.4879, label: 'Hunat Camii' },
    progress: 0.75,
    speed: 0.0040,
    packageCode: 'DLV-9C42',
  },
  {
    id: 'c-4',
    name: 'Ali Şahin',
    avatar: 'AŞ',
    vehicleType: 'motorcycle',
    phone: '+90 544 444 55 66',
    rating: 4.7,
    start: { lat: 38.7655, lng: 35.5170, label: 'Anbar Mah.' },
    end:   { lat: 38.7218, lng: 35.4857, label: 'Kayseri Kalesi' },
    progress: 0.15,
    speed: 0.0030,
    packageCode: 'DLV-5E11',
  },
  {
    id: 'c-5',
    name: 'Zeynep Arslan',
    avatar: 'ZA',
    vehicleType: 'on_foot',
    phone: '+90 551 555 66 77',
    rating: 5.0,
    start: { lat: 38.7372, lng: 35.4234, label: 'Kocasinan Hastane' },
    end:   { lat: 38.7312, lng: 35.4787, label: 'Kayseri Park AVM' },
    progress: 0.45,
    speed: 0.0012,
    packageCode: 'DLV-3F88',
  },
]

const couriers = ref<FakeCourier[]>(
  INITIAL_COURIERS.map(c => ({ ...c, start: { ...c.start }, end: { ...c.end } })),
)
const selectedId = ref<string | null>(null)
const mapReady = ref(false)
const lastUpdated = ref<Date>(new Date())
const loading = ref(false)

let map: any = null
let courierMarkers = new Map<string, any>()
const pickupMarkers = new Map<string, any>()
const dropoffMarkers = new Map<string, any>()
const fullRoutes = new Map<string, any>()
const completedRoutes = new Map<string, any>()
let animationTimer: ReturnType<typeof setInterval> | null = null

const selectedCourier = computed(() =>
  couriers.value.find(c => c.id === selectedId.value) || null,
)

function vehicleIcon(type: VehicleType) {
  const icons: Record<VehicleType, any> = {
    bicycle: PhBicycle,
    motorcycle: PhMotorcycle,
    car: PhCar,
    on_foot: PhPersonSimpleWalk,
  }
  return icons[type]
}

function vehicleLabel(type: VehicleType) {
  const labels: Record<VehicleType, string> = {
    bicycle: 'Bisiklet',
    motorcycle: 'Motosiklet',
    car: 'Araç',
    on_foot: 'Yaya',
  }
  return labels[type]
}

function vehicleEmoji(type: VehicleType) {
  const emojis: Record<VehicleType, string> = {
    bicycle: '🚲',
    motorcycle: '🏍️',
    car: '🚗',
    on_foot: '🚶',
  }
  return emojis[type]
}

function currentLatLng(c: FakeCourier): [number, number] {
  const lat = c.start.lat + (c.end.lat - c.start.lat) * c.progress
  const lng = c.start.lng + (c.end.lng - c.start.lng) * c.progress
  return [lat, lng]
}

function etaMinutes(c: FakeCourier) {
  // basit tahmin: kalan ilerleme * kaba toplam süre
  const remaining = Math.max(0, 1 - c.progress)
  const baseMinutes: Record<VehicleType, number> = {
    on_foot: 45,
    bicycle: 25,
    motorcycle: 15,
    car: 12,
  }
  return Math.max(1, Math.round(remaining * baseMinutes[c.vehicleType]))
}

function distanceKm(c: FakeCourier) {
  const dLat = c.end.lat - c.start.lat
  const dLng = c.end.lng - c.start.lng
  // yaklaşık: 1 derece enlem ≈ 111km, Kayseri'de 1 derece boylam ≈ 87km
  const km = Math.sqrt((dLat * 111) ** 2 + (dLng * 87) ** 2)
  return km.toFixed(1)
}

function createCourierMarker(c: FakeCourier, isSelected: boolean) {
  const L = (window as any).L
  const ring = isSelected ? '#f97316' : '#ea580c'
  const size = isSelected ? 48 : 40
  return L.divIcon({
    html: `
      <div style="position:relative;">
        <div style="
          width:${size}px; height:${size}px;
          background: linear-gradient(135deg, #f97316, #ea580c);
          border: 3px solid ${ring};
          border-radius: 50%;
          display:flex; align-items:center; justify-content:center;
          box-shadow: 0 6px 18px rgba(249,115,22,0.5);
          font-size:${size * 0.5}px;
          ${isSelected ? 'animation: pulse-ring 1.6s ease-out infinite;' : ''}
        ">${vehicleEmoji(c.vehicleType)}</div>
        <div style="
          position:absolute; bottom:-10px; left:50%; transform:translateX(-50%);
          font-size:10px; font-weight:700;
          background:#1e293b; color:#f97316;
          border-radius:6px; padding:2px 6px;
          white-space:nowrap;
          box-shadow:0 2px 6px rgba(0,0,0,0.4);
          border:1px solid rgba(249,115,22,0.3);
        ">${c.name.split(' ')[0]}</div>
      </div>
    `,
    className: '',
    iconSize: [size, size + 14],
    iconAnchor: [size / 2, size / 2],
  })
}

function createPickupIcon(label: string) {
  const L = (window as any).L
  return L.divIcon({
    html: `
      <div style="position:relative;">
        <div style="
          width:28px; height:28px;
          background:#22c55e;
          border:3px solid #fff;
          border-radius:50%;
          display:flex; align-items:center; justify-content:center;
          box-shadow:0 3px 10px rgba(34,197,94,0.5);
          font-size:13px;
        ">📦</div>
        <div style="
          position:absolute; bottom:-18px; left:50%; transform:translateX(-50%);
          font-size:9px; font-weight:600;
          background:#065f46; color:#d1fae5;
          border-radius:4px; padding:1px 5px; white-space:nowrap;
        ">${label}</div>
      </div>
    `,
    className: '',
    iconSize: [28, 44],
    iconAnchor: [14, 14],
  })
}

function createDropoffIcon(label: string) {
  const L = (window as any).L
  return L.divIcon({
    html: `
      <div style="position:relative;">
        <div style="
          width:28px; height:28px;
          background:#ef4444;
          border:3px solid #fff;
          border-radius:50%;
          display:flex; align-items:center; justify-content:center;
          box-shadow:0 3px 10px rgba(239,68,68,0.5);
          font-size:13px;
        ">🏁</div>
        <div style="
          position:absolute; bottom:-18px; left:50%; transform:translateX(-50%);
          font-size:9px; font-weight:600;
          background:#7f1d1d; color:#fee2e2;
          border-radius:4px; padding:1px 5px; white-space:nowrap;
        ">${label}</div>
      </div>
    `,
    className: '',
    iconSize: [28, 44],
    iconAnchor: [14, 14],
  })
}

function renderCourierOnMap(c: FakeCourier) {
  const L = (window as any).L
  if (!map) return

  const isSelected = selectedId.value === c.id
  const current = currentLatLng(c)

  // başlangıç marker'ı
  if (!pickupMarkers.has(c.id)) {
    const m = L.marker([c.start.lat, c.start.lng], {
      icon: createPickupIcon(c.start.label),
    })
      .addTo(map)
      .bindTooltip(`Alış: ${c.start.label}`, { direction: 'top' })
    pickupMarkers.set(c.id, m)
  }

  // bitiş marker'ı
  if (!dropoffMarkers.has(c.id)) {
    const m = L.marker([c.end.lat, c.end.lng], {
      icon: createDropoffIcon(c.end.label),
    })
      .addTo(map)
      .bindTooltip(`Teslim: ${c.end.label}`, { direction: 'top' })
    dropoffMarkers.set(c.id, m)
  }

  // tüm rota (başlangıç -> bitiş, kesikli)
  if (!fullRoutes.has(c.id)) {
    const line = L.polyline(
      [[c.start.lat, c.start.lng], [c.end.lat, c.end.lng]],
      {
        color: isSelected ? '#f97316' : '#64748b',
        weight: isSelected ? 4 : 3,
        opacity: isSelected ? 0.85 : 0.55,
        dashArray: '10, 8',
      },
    ).addTo(map)
    fullRoutes.set(c.id, line)
  } else {
    fullRoutes.get(c.id).setStyle({
      color: isSelected ? '#f97316' : '#64748b',
      weight: isSelected ? 4 : 3,
      opacity: isSelected ? 0.9 : 0.55,
    })
  }

  // tamamlanmış kısım (başlangıç -> mevcut konum, kalın)
  if (completedRoutes.has(c.id)) {
    completedRoutes.get(c.id).setLatLngs([
      [c.start.lat, c.start.lng],
      current,
    ])
    completedRoutes.get(c.id).setStyle({
      color: isSelected ? '#f97316' : '#fb923c',
      weight: isSelected ? 6 : 4,
      opacity: isSelected ? 1 : 0.8,
    })
  } else {
    const line = L.polyline(
      [[c.start.lat, c.start.lng], current],
      { color: '#fb923c', weight: 4, opacity: 0.8 },
    ).addTo(map)
    completedRoutes.set(c.id, line)
  }

  // kurye markeri
  if (courierMarkers.has(c.id)) {
    const marker = courierMarkers.get(c.id)
    marker.setLatLng(current)
    marker.setIcon(createCourierMarker(c, isSelected))
  } else {
    const marker = L.marker(current, {
      icon: createCourierMarker(c, isSelected),
      zIndexOffset: 1000,
    })
      .addTo(map)
      .on('click', () => selectCourier(c.id))
    courierMarkers.set(c.id, marker)
  }
}

function renderAll() {
  couriers.value.forEach(renderCourierOnMap)
}

function selectCourier(id: string) {
  selectedId.value = id
  renderAll()
  const c = couriers.value.find(x => x.id === id)
  if (c && map) {
    const bounds = (window as any).L.latLngBounds([
      [c.start.lat, c.start.lng],
      [c.end.lat, c.end.lng],
    ])
    map.flyToBounds(bounds, { padding: [80, 80], duration: 0.8 })
  }
}

function deselect() {
  selectedId.value = null
  renderAll()
}

function refreshView() {
  loading.value = true
  // basit görsel yenilenme
  setTimeout(() => {
    lastUpdated.value = new Date()
    loading.value = false
  }, 500)
}

// Animasyon: kuryeleri rotaları üzerinde hareket ettir
function tick() {
  couriers.value.forEach(c => {
    c.progress = Math.min(1, c.progress + c.speed)
    // bitirenler yeniden baştan başlasın (simülasyon)
    if (c.progress >= 1) {
      c.progress = 0
    }
  })
  lastUpdated.value = new Date()
  renderAll()
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
  if (!L) return

  map = L.map('kuryem-map', {
    center: KAYSERI_CENTER,
    zoom: 12,
    zoomControl: true,
  })

  // Açık renk, canlı harita: OSM
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '&copy; OpenStreetMap contributors',
    subdomains: 'abc',
    maxZoom: 19,
  }).addTo(map)

  // Kayseri sınırlarını basitçe vurgulamak için şeffaf daire
  L.circle(KAYSERI_CENTER, {
    radius: 10000,
    color: '#f97316',
    weight: 1,
    fillColor: '#f97316',
    fillOpacity: 0.04,
    dashArray: '6, 6',
  }).addTo(map)

  mapReady.value = true
  renderAll()

  // Harita boş bir yere tıklanırsa seçim temizle
  map.on('click', (e: any) => {
    if (!(e.originalEvent.target as HTMLElement).closest('.leaflet-marker-icon')) {
      deselect()
    }
  })

  // Haritayı tüm rotaları kapsayacak şekilde yerleştir
  const bounds = L.latLngBounds(
    couriers.value.flatMap(c => [
      [c.start.lat, c.start.lng] as [number, number],
      [c.end.lat, c.end.lng] as [number, number],
    ]),
  )
  map.fitBounds(bounds, { padding: [60, 60] })
}

onMounted(async () => {
  await loadLeaflet()
  initMap()
  // her 2 saniyede bir konum güncelle (dinamik his)
  animationTimer = setInterval(tick, 2000)
})

onUnmounted(() => {
  if (animationTimer) clearInterval(animationTimer)
  if (map) { map.remove(); map = null }
  courierMarkers.clear()
  pickupMarkers.clear()
  dropoffMarkers.clear()
  fullRoutes.clear()
  completedRoutes.clear()
})
</script>

<template>
  <div class="relative flex h-[calc(100vh-65px)] overflow-hidden bg-stone-50">
    <!-- Sol Panel -->
    <aside class="relative z-10 flex w-80 shrink-0 flex-col border-r border-stone-200 bg-white">
      <!-- Başlık -->
      <div class="border-b border-stone-100 px-5 py-4">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2.5">
            <div class="flex size-9 items-center justify-center rounded-xl bg-orange-100">
              <PhNavigationArrow class="size-5 text-orange-600" weight="duotone" />
            </div>
            <div>
              <h1 class="text-base font-bold text-stone-900">Kuryem Nerede?</h1>
              <p class="text-xs text-stone-500">Kayseri canlı kurye takibi</p>
            </div>
          </div>
          <button
            class="flex size-8 items-center justify-center rounded-lg border border-stone-200 bg-white text-stone-500 transition hover:bg-stone-50 hover:text-stone-900"
            :class="{ 'animate-spin': loading }"
            title="Yenile"
            @click="refreshView"
          >
            <PhArrowClockwise class="size-4" weight="bold" />
          </button>
        </div>

        <!-- Özet -->
        <div class="mt-4 grid grid-cols-3 gap-2 text-center">
          <div class="rounded-lg border border-orange-100 bg-orange-50 px-2 py-2">
            <p class="text-lg font-bold text-orange-600">{{ couriers.length }}</p>
            <p class="text-[10px] font-medium uppercase tracking-wide text-orange-700/70">Kurye</p>
          </div>
          <div class="rounded-lg border border-green-100 bg-green-50 px-2 py-2">
            <p class="text-lg font-bold text-green-600">{{ couriers.length }}</p>
            <p class="text-[10px] font-medium uppercase tracking-wide text-green-700/70">Aktif</p>
          </div>
          <div class="rounded-lg border border-stone-200 bg-stone-50 px-2 py-2">
            <p class="text-lg font-bold text-stone-700">Kayseri</p>
            <p class="text-[10px] font-medium uppercase tracking-wide text-stone-500">Bölge</p>
          </div>
        </div>

        <p class="mt-3 text-center text-[11px] text-stone-400">
          Son güncelleme: {{ lastUpdated.toLocaleTimeString('tr-TR') }}
        </p>
      </div>

      <!-- Kurye Listesi -->
      <div class="flex-1 overflow-y-auto px-3 py-3">
        <p class="mb-2 px-2 text-[10px] font-bold uppercase tracking-widest text-stone-400">
          Yoldaki Kuryeler
        </p>
        <div class="flex flex-col gap-2">
          <button
            v-for="c in couriers"
            :key="c.id"
            class="group flex flex-col gap-2 rounded-xl border px-3 py-3 text-left transition"
            :class="selectedId === c.id
              ? 'border-orange-300 bg-orange-50 shadow-sm ring-1 ring-orange-200'
              : 'border-stone-200 bg-white hover:border-orange-200 hover:bg-orange-50/40'"
            @click="selectCourier(c.id)"
          >
            <div class="flex items-center gap-3">
              <div
                class="relative flex size-10 shrink-0 items-center justify-center rounded-full text-sm font-bold text-white"
                :class="selectedId === c.id ? 'bg-orange-500' : 'bg-stone-700'"
              >
                {{ c.avatar }}
                <span class="absolute -right-0.5 -top-0.5 size-3 rounded-full border-2 border-white bg-green-500" />
              </div>
              <div class="min-w-0 flex-1">
                <p class="truncate text-sm font-semibold text-stone-900">{{ c.name }}</p>
                <p class="mt-0.5 flex items-center gap-1.5 text-xs text-stone-500">
                  <component :is="vehicleIcon(c.vehicleType)" class="size-3.5" weight="bold" />
                  {{ vehicleLabel(c.vehicleType) }}
                  <span class="text-stone-300">•</span>
                  <span class="font-medium text-amber-600">★ {{ c.rating.toFixed(1) }}</span>
                </p>
              </div>
            </div>

            <!-- İlerleme çubuğu -->
            <div>
              <div class="flex items-center justify-between text-[10px] text-stone-400">
                <span class="truncate">{{ c.start.label }}</span>
                <span class="truncate">{{ c.end.label }}</span>
              </div>
              <div class="mt-1 h-1.5 overflow-hidden rounded-full bg-stone-200">
                <div
                  class="h-full rounded-full bg-gradient-to-r from-orange-500 to-amber-400 transition-all duration-700"
                  :style="{ width: `${Math.round(c.progress * 100)}%` }"
                />
              </div>
              <div class="mt-1 flex items-center justify-between text-[10px]">
                <span class="font-semibold text-orange-600">%{{ Math.round(c.progress * 100) }}</span>
                <span class="text-stone-400">~{{ etaMinutes(c) }} dk</span>
              </div>
            </div>
          </button>
        </div>

        <p class="mt-4 px-2 text-center text-[10px] text-stone-400">
          Gösterim amaçlı demo kuryelerdir.
        </p>
      </div>
    </aside>

    <!-- Harita Alanı -->
    <div class="relative flex-1">
      <div id="kuryem-map" class="size-full" />

      <!-- Legend -->
      <div class="absolute left-4 top-4 z-[1000] rounded-xl border border-stone-200 bg-white/95 px-4 py-3 shadow-lg backdrop-blur">
        <p class="mb-2 text-[10px] font-bold uppercase tracking-widest text-stone-500">Harita Göstergesi</p>
        <div class="flex flex-col gap-1.5 text-xs">
          <div class="flex items-center gap-2">
            <span class="flex size-5 items-center justify-center rounded-full bg-green-500 text-[10px] text-white">📦</span>
            <span class="text-stone-700">Başlangıç noktası</span>
          </div>
          <div class="flex items-center gap-2">
            <span class="flex size-5 items-center justify-center rounded-full bg-red-500 text-[10px] text-white">🏁</span>
            <span class="text-stone-700">Bitiş noktası</span>
          </div>
          <div class="flex items-center gap-2">
            <PhPath class="size-4 text-orange-500" weight="bold" />
            <span class="text-stone-700">Kat edilen yol</span>
          </div>
          <div class="flex items-center gap-2">
            <span class="h-0.5 w-5 border-t-2 border-dashed border-stone-400" />
            <span class="text-stone-700">Kalan rota</span>
          </div>
        </div>
      </div>

      <!-- Seçili Kurye Detay Kartı -->
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
          class="absolute bottom-6 left-1/2 z-[1000] w-[min(92vw,520px)] -translate-x-1/2"
        >
          <div class="overflow-hidden rounded-2xl border border-stone-200 bg-white shadow-2xl">
            <div class="flex items-center gap-3 border-b border-stone-100 px-5 py-3">
              <div class="flex size-11 items-center justify-center rounded-xl bg-orange-500 text-base font-bold text-white">
                {{ selectedCourier.avatar }}
              </div>
              <div class="min-w-0 flex-1">
                <p class="truncate font-semibold text-stone-900">{{ selectedCourier.name }}</p>
                <p class="mt-0.5 flex items-center gap-2 text-xs text-stone-500">
                  <component :is="vehicleIcon(selectedCourier.vehicleType)" class="size-3.5" weight="bold" />
                  {{ vehicleLabel(selectedCourier.vehicleType) }}
                  <PhCircle class="size-2 text-green-500" weight="fill" />
                  Yolda
                </p>
              </div>
              <button
                class="rounded-lg p-1.5 text-stone-400 transition hover:bg-stone-100 hover:text-stone-700"
                @click="deselect"
              >
                ✕
              </button>
            </div>

            <div class="grid grid-cols-2 divide-x divide-stone-100">
              <div class="flex items-start gap-2 px-4 py-3">
                <PhPackage class="mt-0.5 size-4 text-green-600" weight="duotone" />
                <div class="min-w-0">
                  <p class="text-[10px] font-semibold uppercase tracking-wide text-stone-400">Alış</p>
                  <p class="truncate text-xs font-medium text-stone-800">{{ selectedCourier.start.label }}</p>
                </div>
              </div>
              <div class="flex items-start gap-2 px-4 py-3">
                <PhFlagCheckered class="mt-0.5 size-4 text-red-500" weight="duotone" />
                <div class="min-w-0">
                  <p class="text-[10px] font-semibold uppercase tracking-wide text-stone-400">Teslim</p>
                  <p class="truncate text-xs font-medium text-stone-800">{{ selectedCourier.end.label }}</p>
                </div>
              </div>
            </div>

            <div class="grid grid-cols-3 gap-2 border-t border-stone-100 bg-stone-50 px-4 py-3 text-center">
              <div>
                <p class="text-base font-bold text-stone-900">%{{ Math.round(selectedCourier.progress * 100) }}</p>
                <p class="text-[10px] uppercase tracking-wide text-stone-500">İlerleme</p>
              </div>
              <div>
                <p class="text-base font-bold text-stone-900">{{ etaMinutes(selectedCourier) }} dk</p>
                <p class="text-[10px] uppercase tracking-wide text-stone-500">Tahmini</p>
              </div>
              <div>
                <p class="text-base font-bold text-stone-900">{{ distanceKm(selectedCourier) }} km</p>
                <p class="text-[10px] uppercase tracking-wide text-stone-500">Mesafe</p>
              </div>
            </div>

            <div class="flex items-center justify-between border-t border-stone-100 px-4 py-2.5 text-xs">
              <span class="font-mono text-stone-500">{{ selectedCourier.packageCode }}</span>
              <a
                :href="`tel:${selectedCourier.phone.replace(/\s/g, '')}`"
                class="font-medium text-orange-600 hover:text-orange-700"
              >
                {{ selectedCourier.phone }}
              </a>
            </div>
          </div>
        </div>
      </Transition>
    </div>
  </div>
</template>

<style>
@keyframes pulse-ring {
  0%   { box-shadow: 0 6px 18px rgba(249,115,22,0.5), 0 0 0 0 rgba(249,115,22,0.55); }
  70%  { box-shadow: 0 6px 18px rgba(249,115,22,0.5), 0 0 0 18px rgba(249,115,22,0); }
  100% { box-shadow: 0 6px 18px rgba(249,115,22,0.5), 0 0 0 0 rgba(249,115,22,0); }
}
</style>
