<script setup lang="ts">
import { onMounted, onUnmounted, ref } from 'vue'
import { PhBicycle, PhCheck, PhGavel, PhLockKey, PhSealCheck, PhShieldCheck, PhShieldChevron, PhUser, PhUserCircle } from '@phosphor-icons/vue'

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

const CYCLE_MS = 4200

const section = ref<HTMLElement | null>(null)
const activeLayer = ref(0)
const progress = ref(0)
const reducedMotion = ref(false)
const visible = ref(false)

let raf = 0
let lastTs = 0
let observer: IntersectionObserver | undefined
let preference: MediaQueryList | undefined

function tick(ts: number) {
  if (!lastTs) lastTs = ts
  const delta = ts - lastTs
  lastTs = ts
  if (visible.value && !reducedMotion.value) {
    progress.value += (delta / CYCLE_MS) * 100
    if (progress.value >= 100) {
      progress.value = 0
      activeLayer.value = (activeLayer.value + 1) % layers.length
    }
  }
  raf = requestAnimationFrame(tick)
}

function selectLayer(i: number) {
  activeLayer.value = i
  progress.value = 0
}

function syncReducedMotion() {
  reducedMotion.value = preference?.matches ?? false
}

function trackScale(i: number) {
  if (i < activeLayer.value) return 1
  if (i > activeLayer.value) return 0
  return progress.value / 100
}

onMounted(() => {
  preference = window.matchMedia('(prefers-reduced-motion: reduce)')
  syncReducedMotion()
  preference.addEventListener('change', syncReducedMotion)
  if (section.value) {
    observer = new IntersectionObserver(
      ([entry]) => { visible.value = entry?.isIntersecting ?? false },
      { threshold: 0.35 },
    )
    observer.observe(section.value)
  }
  raf = requestAnimationFrame(tick)
})
onUnmounted(() => {
  cancelAnimationFrame(raf)
  observer?.disconnect()
  preference?.removeEventListener('change', syncReducedMotion)
})
</script>

<template>
  <section id="security" ref="section" class="trust-section">
    <div class="trust-container">
      <header class="trust-heading">
        <div>
          <p class="trust-kicker"><span /> GÜVENLİK</p>
          <h2>4 Katmanlı <span>Güven</span></h2>
        </div>
        <p>Teslimat sektörünün en büyük sorunu güvensizliktir. Delivera, her işlemi blockchain güvencesiyle sarar.</p>
      </header>
    </div>

    <div class="trust-container">
      <div class="trust-panel">
        <div class="trust-topline">
          <span><ph-shield-check weight="duotone" /> GÜVEN KATMANLARI</span>
          <span class="trust-tags">
            <span><i />Sıfır güven riski</span>
            <span><i />Tamamen şeffaf</span>
            <span><i />Değiştirilemez</span>
          </span>
        </div>

        <div class="trust-body">
          <div class="trust-scene">
            <div class="trust-scene-glow" aria-hidden="true" />
            <Transition name="trust-scene" mode="out-in">
              <div :key="activeLayer" class="trust-scene-inner">
                <template v-if="activeLayer === 0">
                  <div class="trust-vault-wrap">
                    <div class="trust-vault"><ph-lock-key weight="duotone" /></div>
                    <span class="trust-vault-badge"><ph-check weight="bold" /></span>
                  </div>
                  <p class="trust-scene-caption">Ödeme, akıllı sözleşmede kilitli — teslim edilene kadar kimse dokunamaz.</p>
                </template>

                <template v-else-if="activeLayer === 1">
                  <div class="trust-approval">
                    <div class="trust-approval-step">
                      <span class="trust-approval-avatar"><ph-bicycle weight="duotone" /></span>
                      <span class="trust-approval-label">Kurye alım onayı</span>
                      <span class="trust-approval-check"><ph-check weight="bold" /></span>
                    </div>
                    <span class="trust-approval-line"><span /></span>
                    <div class="trust-approval-step">
                      <span class="trust-approval-avatar"><ph-user weight="duotone" /></span>
                      <span class="trust-approval-label">Alıcı teslim onayı</span>
                      <span class="trust-approval-check" style="animation-delay: 1.4s"><ph-check weight="bold" /></span>
                    </div>
                  </div>
                  <p class="trust-scene-caption">İki taraf da onaylamadan ödeme serbest kalmaz.</p>
                </template>

                <template v-else-if="activeLayer === 2">
                  <div class="trust-deposit">
                    <span class="trust-deposit-courier"><ph-bicycle weight="duotone" /></span>
                    <img src="/monad-coin.svg" alt="" class="trust-deposit-coin">
                    <div class="trust-deposit-shield"><ph-shield-chevron weight="duotone" /></div>
                  </div>
                  <p class="trust-scene-caption">Kurye teklif verirken teminat yatırır — işi bırakırsa müşteriye gider.</p>
                </template>

                <template v-else>
                  <div class="trust-jury">
                    <ph-gavel class="trust-gavel" weight="fill" />
                    <span v-for="n in 7" :key="n" class="trust-juror" :class="{ 'is-voting': n === 4 }" :style="{ '--juror-index': n }">
                      <ph-user-circle weight="fill" />
                    </span>
                  </div>
                  <p class="trust-scene-caption">Rastgele seçilen token sahipleri delilleri inceler, karar zincire yazılır.</p>
                </template>
              </div>
            </Transition>
          </div>

          <div class="trust-list">
            <button
              v-for="(layer, i) in layers"
              :key="layer.num"
              type="button"
              class="trust-item"
              :class="{ 'is-active': i === activeLayer }"
              @click="selectLayer(i)"
            >
              <span class="trust-item-track"><span :style="{ transform: `scaleX(${trackScale(i)})` }" /></span>
              <span class="trust-item-top">
                <span class="trust-item-icon"><component :is="layer.icon" weight="duotone" /></span>
                <span class="trust-item-num">Katman {{ layer.num }}</span>
              </span>
              <strong class="trust-item-title">{{ layer.title }}</strong>
              <p class="trust-item-desc" :class="{ 'is-hidden': i !== activeLayer }">{{ layer.desc }}</p>
            </button>
          </div>
        </div>
      </div>
    </div>
  </section>
</template>
