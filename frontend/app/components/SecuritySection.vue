<script setup lang="ts">
import { PhLockKey, PhSealCheck, PhShieldChevron, PhGavel } from '@phosphor-icons/vue'

const layers = [
  {
    num: '1', title: 'Escrow Ödeme',
    icon: PhLockKey,
    desc: 'Müşterinin parası teslimat tamamlanana kadar kilitlenir. Hiçbir taraf tek başına dokunabilir.',
  },
  {
    num: '2', title: 'İki Aşamalı Onay',
    icon: PhSealCheck,
    desc: 'Kurye ürünü alırken müşteri, teslim ederken alıcı onaylar. İkisi olmadan ödeme serbest kalmaz.',
  },
  {
    num: '3', title: 'Teminat Mekanizması',
    icon: PhShieldChevron,
    desc: 'Kurye teklif verirken teminat yatırır. İşi bırakırsa teminat müşteriye gider.',
  },
  {
    num: '4', title: 'Jüri Sistemi',
    icon: PhGavel,
    desc: 'Uyuşmazlıkta rastgele token sahipleri delilleri inceler. Karar blockchain\'e yazılır.',
  },
]
</script>

<template>
  <section class="px-5 py-16 sm:px-8">
    <div class="mx-auto max-w-6xl">
      <div class="grid gap-10 lg:grid-cols-2 lg:items-start">
        <div>
          <p class="mb-2 text-xs font-semibold uppercase tracking-widest text-orange-500">Güvenlik</p>
          <h2 class="mb-4 text-2xl font-bold text-stone-900 sm:text-3xl">4 Katmanlı Güven</h2>
          <p class="text-stone-500 leading-relaxed">
            Teslimat sektörünün en büyük sorunu güvensizliktir. Delivera, her işlemi
            blockchain güvencesiyle sararak bu sorunu tamamen çözer.
          </p>
          <div class="mt-6 flex flex-wrap gap-3 text-sm">
            <span class="flex items-center gap-1.5 text-stone-600">
              <span class="size-2 rounded-full bg-orange-400" />Sıfır güven riski
            </span>
            <span class="flex items-center gap-1.5 text-stone-600">
              <span class="size-2 rounded-full bg-orange-400" />Tamamen şeffaf
            </span>
            <span class="flex items-center gap-1.5 text-stone-600">
              <span class="size-2 rounded-full bg-orange-400" />Değiştirilemez
            </span>
          </div>
        </div>

        <div class="space-y-3">
          <div
            v-for="layer in layers"
            :key="layer.num"
            class="flex items-start gap-4 rounded-xl border border-orange-200 bg-orange-50 p-4"
          >
            <div class="flex size-9 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-orange-100 to-amber-50 text-orange-500 ring-1 ring-orange-200/60">
              <component :is="layer.icon" class="size-5" weight="duotone" />
            </div>
            <div>
              <div class="mb-0.5 flex items-center gap-2">
                <span class="text-xs font-bold text-stone-400">Katman {{ layer.num }}</span>
                <h3 class="text-sm font-semibold text-stone-900">{{ layer.title }}</h3>
              </div>
              <p class="text-xs leading-relaxed text-stone-600">{{ layer.desc }}</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>
</template>
