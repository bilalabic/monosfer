<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { PhPackage, PhBicycle, PhCheckCircle, PhCoins } from '@phosphor-icons/vue'
import { onSpotlightMouseMove, onTiltMouseMove, onTiltMouseLeave } from '@/composables/useSpotlight'

function onCardMouseMove(e: MouseEvent) {
  onSpotlightMouseMove(e)
  onTiltMouseMove(e)
}

const stats = [
  { value: 1247, suffix: '', label: 'Toplam Teslimat', icon: PhPackage },
  { value: 342, suffix: '+', label: 'Aktif Kurye', icon: PhBicycle },
  { value: 98.4, suffix: '%', label: 'Başarı Oranı', icon: PhCheckCircle },
  { value: 24680, suffix: '', label: 'Dağıtılan MON', icon: PhCoins },
]

const displayed = ref(stats.map(() => 0))
const animated = ref(false)

onMounted(() => {
  const observer = new IntersectionObserver(
    ([entry]) => {
      if (!entry) return

      if (entry.isIntersecting && !animated.value) {
        animated.value = true
        stats.forEach((stat, i) => {
          const duration = 1600
          const start = performance.now()
          const run = (now: number) => {
            const t = Math.min((now - start) / duration, 1)
            const eased = 1 - Math.pow(1 - t, 3)
            displayed.value[i] = parseFloat((stat.value * eased).toFixed(stat.suffix === '%' ? 1 : 0))
            if (t < 1) requestAnimationFrame(run)
            else displayed.value[i] = stat.value
          }
          requestAnimationFrame(run)
        })
      }
    },
    { threshold: 0.4 },
  )
  const el = document.getElementById('stats-section')
  if (el) observer.observe(el)
})
</script>

<template>
  <section id="stats-section" class="px-5 py-12 sm:px-8 bg-stone-50">
    <div class="mx-auto max-w-6xl">
      <div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <div
          v-for="(stat, i) in stats"
          :key="stat.label"
          v-reveal="{ delay: i * 100, type: '3d' }"
          class="spotlight-card rounded-xl border border-stone-200 bg-white shadow-sm transition-shadow duration-300 hover:shadow-lg"
          @mousemove="onCardMouseMove"
          @mouseleave="onTiltMouseLeave"
        >
          <div class="tilt-card p-5 text-center">
            <div class="mx-auto mb-3 flex size-10 items-center justify-center rounded-full bg-orange-50">
              <component :is="stat.icon" class="size-5 text-orange-500" weight="duotone" />
            </div>
            <div class="text-3xl font-extrabold tabular-nums text-orange-600">
              {{ stat.suffix === '%' ? Number(displayed[i] ?? 0).toFixed(1) : Number(displayed[i] ?? 0).toLocaleString('tr-TR') }}{{ stat.suffix }}
            </div>
            <div class="mt-1 text-sm font-medium text-stone-600">{{ stat.label }}</div>
          </div>
        </div>
      </div>
    </div>
  </section>
</template>
