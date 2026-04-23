<script setup lang="ts">
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { PhArrowLeft as ArrowLeft, PhMapPin as MapPin, PhClock as Clock, PhBarbell as Weight, PhPackage as Package, PhShieldCheck as Shield, PhUsers as Users } from '@phosphor-icons/vue'
import { useDeliveryStore } from '@/stores/useDeliveryStore'
import StatusBadge from '@/components/StatusBadge.vue'
import TokenAmount from '@/components/TokenAmount.vue'
import CourierBidCard from '@/components/CourierBidCard.vue'
import DeliveryTimeline from '@/components/DeliveryTimeline.vue'

const route = useRoute()
const router = useRouter()
const store = useDeliveryStore()
const delivery = computed(() => store.getDelivery(route.params.id as string))

function formatDate(s: string) {
  return new Date(s).toLocaleString('tr-TR', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
}
</script>

<template>
  <div v-if="delivery" class="mx-auto max-w-5xl px-5 py-10 sm:px-8">
    <button class="mb-5 flex items-center gap-1.5 text-sm text-stone-500 transition hover:text-stone-900" @click="router.back()">
      <ArrowLeft class="size-4" weight="bold" /> Teslimatlar
    </button>

    <!-- Header -->
    <div class="mb-7 flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
      <div>
        <div class="mb-2 flex items-center gap-3">
          <div class="flex size-9 items-center justify-center rounded-lg bg-orange-100">
            <Package class="size-5 text-orange-600" weight="duotone" />
          </div>
          <h1 class="text-xl font-bold text-stone-900">{{ delivery.title }}</h1>
        </div>
        <div class="flex flex-wrap items-center gap-3">
          <StatusBadge :status="delivery.status" />
          <span class="text-xs text-stone-400">{{ formatDate(delivery.createdAt) }}</span>
        </div>
      </div>
      <div class="flex flex-col items-start sm:items-end gap-1">
        <p class="text-xs text-stone-400">Escrow'daki tutar</p>
        <TokenAmount :amount="delivery.escrowAmount" size="lg" />
      </div>
    </div>

    <div class="grid gap-5 lg:grid-cols-3">
      <!-- Left col -->
      <div class="lg:col-span-2 space-y-4">
        <!-- Route -->
        <div class="card rounded-xl bg-white p-5">
          <p class="mb-4 text-xs font-semibold uppercase tracking-wide text-stone-400">Rota</p>
          <div class="space-y-3">
            <div class="flex items-center gap-3">
              <div class="flex size-7 shrink-0 items-center justify-center rounded-lg bg-green-100"><span class="size-2 rounded-full bg-green-500" /></div>
              <div><p class="text-xs text-stone-400">Alış</p><p class="text-sm font-medium text-stone-900">{{ delivery.pickupAddress }}</p></div>
            </div>
            <div class="ml-3.5 h-4 w-px bg-stone-200" />
            <div class="flex items-center gap-3">
              <div class="flex size-7 shrink-0 items-center justify-center rounded-lg bg-red-100"><span class="size-2 rounded-full bg-red-400" /></div>
              <div><p class="text-xs text-stone-400">Teslim</p><p class="text-sm font-medium text-stone-900">{{ delivery.dropoffAddress }}</p></div>
            </div>
          </div>
        </div>

        <!-- Info grid -->
        <div class="grid grid-cols-3 gap-3">
          <div class="card rounded-xl bg-white p-4 text-center">
            <MapPin class="mx-auto mb-1.5 size-5 text-stone-400" weight="fill" />
            <p class="text-sm font-bold text-stone-900">{{ delivery.distance }}</p>
            <p class="text-xs text-stone-400">Mesafe</p>
          </div>
          <div class="card rounded-xl bg-white p-4 text-center">
            <Weight class="mx-auto mb-1.5 size-5 text-stone-400" weight="fill" />
            <p class="text-sm font-bold text-stone-900">{{ delivery.weight }}</p>
            <p class="text-xs text-stone-400">Ağırlık</p>
          </div>
          <div class="card rounded-xl bg-white p-4 text-center">
            <Clock class="mx-auto mb-1.5 size-5 text-stone-400" weight="fill" />
            <p class="text-sm font-bold text-stone-900">{{ new Date(delivery.deadline).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' }) }}</p>
            <p class="text-xs text-stone-400">Son Saat</p>
          </div>
        </div>

        <!-- Description -->
        <div v-if="delivery.description" class="card rounded-xl bg-white p-5">
          <p class="mb-2 text-xs font-semibold uppercase tracking-wide text-stone-400">Açıklama</p>
          <p class="text-sm leading-relaxed text-stone-600">{{ delivery.description }}</p>
        </div>

        <!-- Bids -->
        <div class="card rounded-xl bg-white p-5">
          <p class="mb-4 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-stone-400">
            <Users class="size-4" weight="fill" /> Teklifler ({{ delivery.bids.length }})
          </p>
          <div v-if="delivery.bids.length > 0" class="space-y-3">
            <CourierBidCard
              v-for="bid in delivery.bids"
              :key="bid.id"
              :bid="bid"
              :is-selected="delivery.selectedBidId === bid.id"
              :can-select="delivery.status === 'open'"
              @select="store.selectBid(delivery!.id, $event)"
            />
          </div>
          <div v-else class="py-8 text-center">
            <p class="text-3xl mb-2">⏳</p>
            <p class="text-sm text-stone-500">Henüz teklif yok.</p>
          </div>
        </div>
      </div>

      <!-- Right col -->
      <div class="space-y-4">
        <!-- Timeline -->
        <div class="card rounded-xl bg-white p-5">
          <p class="mb-5 text-xs font-semibold uppercase tracking-wide text-stone-400">Teslimat Süreci</p>
          <DeliveryTimeline :timeline="delivery.timeline" />
        </div>

        <!-- Escrow badge -->
        <div class="rounded-xl border border-orange-200 bg-orange-50 p-5">
          <div class="mb-2 flex items-center gap-2">
            <Shield class="size-5 text-orange-600" weight="duotone" />
            <p class="text-sm font-semibold text-orange-700">Escrow Güvencesi</p>
          </div>
          <p class="text-xs leading-relaxed text-stone-600">
            Ödemeniz teslimat tamamlanana kadar akıllı sözleşmede bekler. Hiç kimse tek başına dokunamaz.
          </p>
          <div class="mt-3 rounded-lg bg-white border border-orange-100 p-2.5 text-center">
            <TokenAmount :amount="delivery.escrowAmount" size="sm" />
            <p class="mt-0.5 text-xs text-stone-400">Kilitli</p>
          </div>
        </div>
      </div>
    </div>
  </div>

  <div v-else class="flex h-64 flex-col items-center justify-center gap-3">
    <div class="text-4xl">🔍</div>
    <h2 class="font-semibold text-stone-900">Teslimat bulunamadı</h2>
    <button class="btn-primary" @click="router.push('/deliveries')">
      <ArrowLeft class="size-4" weight="bold" /> Teslimatlar
    </button>
  </div>
</template>
