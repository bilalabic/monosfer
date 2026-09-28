<script setup lang="ts">
import { computed } from 'vue'
import { PhMapPin as MapPin, PhClock as Clock, PhBarbell as Weight, PhPackage as Package, PhCaretRight as ChevronRight, PhLockKey, PhQrCode } from '@phosphor-icons/vue'
import type { Delivery } from '@/stores/useDeliveryStore'
import { useWalletStore } from '@/stores/useWalletStore'
import StatusBadge from '@/components/StatusBadge.vue'
import TokenAmount from '@/components/TokenAmount.vue'

const props = defineProps<{ delivery: Delivery }>()
const emit = defineEmits<{ bid: [deliveryId: string] }>()

const router = useRouter()
const wallet = useWalletStore()

const isOwner = computed(() => !!wallet.address && wallet.address.toLowerCase() === props.delivery.senderId?.toLowerCase())
const isAssignedCourier = computed(() => !!wallet.address && wallet.address.toLowerCase() === props.delivery.assignedCourierId?.toLowerCase())
const hasUserBid = computed(() =>
  !!wallet.address &&
  props.delivery.bids.some(bid => bid.courierId.toLowerCase() === wallet.address.toLowerCase()),
)

function formatTime(dateStr: string) {
  return new Date(dateStr).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' })
}
</script>

<template>
  <div class="card card-hover flex h-full min-w-0 flex-col rounded-xl bg-white p-5">
    <!-- Header -->
    <div class="mb-4 flex items-start justify-between gap-3">
      <div class="flex min-w-0 items-center gap-3">
        <div class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-orange-100">
          <Package class="size-5 text-orange-600" weight="duotone" />
        </div>
        <div class="min-w-0">
          <h3 class="line-clamp-2 text-sm font-semibold leading-tight text-stone-900">{{ delivery.title }}</h3>
          <p class="text-xs text-stone-400 mt-0.5">{{ formatTime(delivery.createdAt) }} · {{ delivery.bids.length }} teklif</p>
        </div>
      </div>
      <StatusBadge class="shrink-0" :status="delivery.status" />
    </div>

    <!-- Route -->
    <div class="mb-4 rounded-lg border border-stone-100 bg-stone-50 p-3 space-y-2">
      <div class="flex items-center gap-2 text-xs">
        <span class="size-1.5 rounded-full bg-green-500 shrink-0" />
        <span class="text-stone-600 truncate">{{ delivery.pickupAddress }}</span>
      </div>
      <div class="ml-[3px] h-3 w-px bg-stone-300" />
      <div class="flex items-center gap-2 text-xs">
        <span class="size-1.5 rounded-full bg-red-400 shrink-0" />
        <span class="text-stone-600 truncate">{{ delivery.dropoffAddress }}</span>
      </div>
    </div>

    <!-- Meta -->
    <div class="mb-5 grid gap-2 text-xs text-stone-400 sm:grid-cols-3">
      <span class="flex min-w-0 items-center gap-1"><MapPin class="size-4 shrink-0" weight="fill" />{{ delivery.distance }}</span>
      <span class="flex min-w-0 items-center gap-1"><Weight class="size-4 shrink-0" weight="fill" />{{ delivery.weight }}</span>
      <span class="flex min-w-0 items-center gap-1"><Clock class="size-4 shrink-0" weight="fill" />{{ formatTime(delivery.deadline) }}'e kadar</span>
    </div>

    <!-- Budget & Actions -->
    <div class="mt-auto flex flex-col gap-4 border-t border-stone-100 pt-4">
      <div>
        <p class="text-xs text-stone-400 mb-0.5">Maks. bütçe</p>
        <TokenAmount :amount="delivery.maxBudget" size="md" />
      </div>
      <div class="grid grid-cols-2 gap-2">
        <button
          v-if="delivery.status === 'open' && !isOwner && !hasUserBid"
          class="btn-primary px-3 py-2 text-xs"
          @click="emit('bid', delivery.id)"
        >
          Teklif Ver
        </button>
        <div
          v-else-if="delivery.status === 'open' && !isOwner && hasUserBid"
          class="flex items-center justify-center rounded-lg border border-green-200 bg-green-50 px-3 py-2 text-xs font-medium text-green-700"
        >
          Teklif verildi
        </div>
        <button
          v-if="delivery.chainState === 'AwaitingFunding' && isOwner && !delivery.customerFunded"
          class="flex items-center justify-center gap-1 rounded-lg border border-orange-200 bg-orange-50 px-3 py-2 text-xs font-medium text-orange-700 transition hover:bg-orange-100"
          @click="router.push(`/payment/${delivery.id}`)"
        >
          <PhLockKey class="size-3.5" weight="bold" /> Öde
        </button>
        <div
          v-else-if="delivery.chainState === 'AwaitingFunding' && isOwner && delivery.customerFunded"
          class="flex items-center justify-center gap-1 rounded-lg border border-green-200 bg-green-50 px-3 py-2 text-xs font-medium text-green-700"
        >
          <PhLockKey class="size-3.5" weight="bold" /> Kilitli
        </div>
        <button
          v-if="['AwaitingFunding', 'ReadyForPickup', 'InTransit', 'DeliveredPending'].includes(delivery.chainState) && delivery.selectedBidId && isAssignedCourier"
          class="flex items-center justify-center gap-1 rounded-lg border border-green-200 bg-green-50 px-3 py-2 text-xs font-medium text-green-700 transition hover:bg-green-100"
          @click="router.push(`/courier/receive/${delivery.id}`)"
        >
          <PhQrCode class="size-3.5" weight="bold" /> Kurye Akışı
        </button>
        <NuxtLink
          :to="`/delivery/${delivery.id}`"
          class="flex items-center justify-center gap-1 rounded-lg border border-stone-200 bg-stone-50 px-3 py-2 text-xs font-medium text-stone-600 transition hover:bg-stone-100"
        >
          Detay <ChevronRight class="size-3.5" weight="bold" />
        </NuxtLink>
      </div>
    </div>
  </div>
</template>
