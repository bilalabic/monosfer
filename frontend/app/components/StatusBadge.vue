<script setup lang="ts">
import type { DeliveryStatus } from '@/stores/useDeliveryStore'

type Status = DeliveryStatus
const props = defineProps<{ status: Status }>()

const config = {
  open: { label: 'Açık', class: 'bg-green-50 text-green-700 border-green-200' },
  in_progress: { label: 'Devam Ediyor', class: 'bg-blue-50 text-blue-700 border-blue-200' },
  completed: { label: 'Tamamlandı', class: 'bg-stone-100 text-stone-600 border-stone-200' },
  returned: { label: 'İade Edildi', class: 'bg-purple-50 text-purple-700 border-purple-200' },
  resolved: { label: 'Çözüldü', class: 'bg-teal-50 text-teal-700 border-teal-200' },
  cancelled: { label: 'İptal Edildi', class: 'bg-red-50 text-red-700 border-red-200' },
  expired: { label: 'Süresi Doldu', class: 'bg-amber-50 text-amber-700 border-amber-200' },
  disputed: { label: 'Uyuşmazlık', class: 'bg-red-50 text-red-700 border-red-200' },
}
</script>

<template>
  <span :class="['inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs font-medium', config[props.status].class]">
    <span class="size-1.5 rounded-full bg-current" />
    {{ config[props.status].label }}
  </span>
</template>
