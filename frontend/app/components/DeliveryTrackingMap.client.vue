<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { PhMapPin, PhLockKey, PhWarning, PhCircleNotch } from '@phosphor-icons/vue'
import { trackingApi, type TrackingSession } from '@/api/tracking'
import { useTrackingEvents, type TrackingSseEvent } from '@/composables/useTrackingEvents'
import { createLeafletMap, destroyLeafletMap } from '@/composables/useLeafletMap'
import { createCourierMarkerIcon } from '@/composables/useMapMarkerIcons'
import type { ChainDeliveryState } from '@/api/deliveries'

const props = defineProps<{
  deliveryId: string
  chainState: ChainDeliveryState
  isOwner: boolean
  isAssignedCourier: boolean
  vehicleType?: string
  courierName?: string
}>()

// Backend only issues tracking sessions while the delivery is in one of these states.
const TRACKABLE_STATES: ChainDeliveryState[] = ['ReadyForPickup', 'InTransit']
const trackable = computed(() =>
  TRACKABLE_STATES.includes(props.chainState) && (props.isOwner || props.isAssignedCourier),
)

const mapElementId = `tracking-map-${props.deliveryId}`
const mapReady = ref(false)
const starting = ref(false)
const error = ref('')
const hasLocation = ref(false)
const lastUpdatedAt = ref<string | null>(null)

let map: L.Map | null = null
let marker: L.Marker | null = null
let session: TrackingSession | null = null
let geoWatchId: number | null = null
let sequence = 0

const events = useTrackingEvents()

function upsertMarker(lat: number, lng: number) {
  if (!map) return
  if (marker) {
    marker.setLatLng([lat, lng])
  } else {
    const icon = createCourierMarkerIcon({
      vehicleType: props.vehicleType ?? 'motorcycle',
      name: props.courierName ?? 'Kurye',
      pulse: true,
    })
    marker = L.marker([lat, lng], { icon }).addTo(map)
  }
  map.panTo([lat, lng])
  hasLocation.value = true
}

function handleSseEvent(event: TrackingSseEvent) {
  if (event.type === 'location' && event.payload.location) {
    lastUpdatedAt.value = event.payload.location.capturedAt
    upsertMarker(event.payload.location.lat, event.payload.location.lng)
  } else if (event.type === 'reset') {
    if (event.payload) {
      lastUpdatedAt.value = event.payload.capturedAt
      upsertMarker(event.payload.lat, event.payload.lng)
    } else {
      hasLocation.value = false
    }
  } else if (event.type === 'closed') {
    error.value = `Takip oturumu kapandı (${event.payload.reason}).`
  }
}

async function startViewMode() {
  map = createLeafletMap(mapElementId, { center: [38.7205, 35.4826], zoom: 14 })
  mapReady.value = true
  session = await trackingApi.startSession(props.deliveryId)
  const current = await trackingApi.getLocation(props.deliveryId, session.trackingSession)
  if (current.location) {
    lastUpdatedAt.value = current.location.capturedAt
    upsertMarker(current.location.lat, current.location.lng)
  }
  void events.connect(props.deliveryId, session.trackingSession, handleSseEvent)
}

async function startPublishMode() {
  session = await trackingApi.startSession(props.deliveryId)
  if (!navigator.geolocation) {
    error.value = 'Bu cihazda konum servisi bulunamadı.'
    return
  }
  geoWatchId = navigator.geolocation.watchPosition(
    (position) => {
      if (!session) return
      sequence += 1
      trackingApi
        .postLocation(props.deliveryId, session.trackingSession, {
          lat: position.coords.latitude,
          lng: position.coords.longitude,
          sequence,
          capturedAt: new Date(position.timestamp).toISOString(),
          accuracyMeters: position.coords.accuracy ?? undefined,
        })
        .then(() => { lastUpdatedAt.value = new Date(position.timestamp).toISOString() })
        .catch(() => {
          // A single missed publish tick shouldn't stop the watch — the next tick retries.
        })
    },
    () => { error.value = 'Konum izni verilmedi.' },
    { enableHighAccuracy: true, maximumAge: 2000, timeout: 10000 },
  )
}

async function teardown() {
  events.stop()
  if (geoWatchId !== null) {
    navigator.geolocation.clearWatch(geoWatchId)
    geoWatchId = null
  }
  if (session) {
    const activeSession = session
    session = null
    await trackingApi.endSession(props.deliveryId, activeSession.trackingSession).catch(() => {})
  }
  map = destroyLeafletMap(map)
  marker = null
  mapReady.value = false
  hasLocation.value = false
}

async function start() {
  if (starting.value) return
  starting.value = true
  error.value = ''
  try {
    if (props.isAssignedCourier) await startPublishMode()
    else await startViewMode()
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : 'Takip başlatılamadı'
  } finally {
    starting.value = false
  }
}

onMounted(() => { if (trackable.value) start() })
onUnmounted(teardown)
watch(trackable, async (isTrackable) => {
  await teardown()
  if (isTrackable) await start()
})
</script>

<template>
  <div v-if="trackable" class="overflow-hidden rounded-2xl border border-stone-200 bg-white">
    <div :id="mapElementId" class="h-64 w-full" />
    <div class="flex items-center justify-between gap-2 border-t border-stone-100 px-4 py-2.5 text-xs">
      <span class="flex items-center gap-1.5 text-stone-500">
        <PhCircleNotch v-if="starting" class="size-3.5 animate-spin" />
        <span v-else class="size-2 rounded-full" :class="hasLocation ? 'bg-green-500' : 'bg-stone-300'" />
        {{ isAssignedCourier ? 'Konumunuz paylaşılıyor' : (hasLocation ? 'Canlı konum aktif' : 'Konum bekleniyor') }}
      </span>
      <span v-if="lastUpdatedAt" class="text-stone-400">{{ new Date(lastUpdatedAt).toLocaleTimeString('tr-TR') }}</span>
    </div>
    <p v-if="error" class="border-t border-red-100 bg-red-50 px-4 py-2 text-xs text-red-600">{{ error }}</p>
  </div>

  <div v-else class="rounded-2xl border border-stone-200 bg-stone-50 p-5">
    <div class="flex items-start gap-3">
      <div class="flex size-9 shrink-0 items-center justify-center rounded-xl bg-stone-200 text-stone-600">
        <PhWarning v-if="!isOwner && !isAssignedCourier" class="size-5" weight="duotone" />
        <PhLockKey v-else class="size-5" weight="duotone" />
      </div>
      <div>
        <p class="text-sm font-semibold text-stone-800">Canlı konum şu an kullanılamıyor</p>
        <p class="mt-1 text-xs leading-relaxed text-stone-500">
          Takip yalnız katılımcıya özel, süreli oturumlarla ve teslimat "Teslim Almaya Hazır" veya "Yolda" durumundayken açılır.
        </p>
        <p class="mt-2 flex items-center gap-1 text-xs font-medium text-stone-600">
          <PhMapPin class="size-3.5" weight="bold" /> Teslimat {{ deliveryId }}
        </p>
      </div>
    </div>
  </div>
</template>
