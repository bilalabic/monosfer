<script setup lang="ts">
import { computed, ref, watch, onUnmounted } from 'vue'
import {
  PhArrowDown, PhArrowLeft, PhArrowRight,
  PhCheck, PhCheckCircle, PhCoins, PhCube, PhHandCoins, PhLockKey,
  PhMapPin, PhPackage, PhPause, PhPlay, PhShieldCheck, PhStar,
  PhTarget, PhTrophy, PhWallet,
} from '@phosphor-icons/vue'
import { useDeliveryJourney } from '@/composables/useDeliveryJourney'
import { useNavbarVisibility } from '@/composables/useNavbarVisibility'
import DeliveryJourneyScene from '@/components/DeliveryJourneyScene.vue'

const steps = [
  { label: 'Talep oluştur', icon: PhPackage, eyebrow: 'HER YOLCULUK BİR PAKETLE BAŞLAR', title: 'Sen talep et.\nGüvenle yola çıksın.', description: 'Alım ve teslimat noktalarını belirle. Ödemen akıllı sözleşmede güvenceye alınsın; paket teslim edilene kadar korunsun.', tag: 'Ödeme güvende', detail: 'Akıllı sözleşme koruması', detailIcon: PhLockKey },
  { label: 'Teklifleri gör', icon: PhHandCoins, eyebrow: 'FİYATI REKABET BELİRLESİN', title: 'Tek paket.\nBirden fazla teklif.', description: 'Kuryeler teslimatın için kendi fiyatlarını belirler. Teminatlı teklifleri tek yerde karşılaştır, seçeneklerini gör.', tag: 'Teminatlı teklifler', detail: 'Şeffaf fiyat karşılaştırması', detailIcon: PhCoins },
  { label: 'Kuryeni seç', icon: PhTarget, eyebrow: 'KONTROL HER ZAMAN SENDE', title: 'İçine sinen\nkuryeyle devam et.', description: 'Fiyatı, puanı ve tamamlanan teslimatları değerlendir. Paketini kime emanet edeceğine sen karar ver.', tag: 'Seçim senin', detail: 'Puan ve teslimat geçmişi', detailIcon: PhStar },
  { label: 'Yolculuğu izle', icon: PhMapPin, eyebrow: 'YOLA ÇIKTIĞI ANDAN KAPINA KADAR', title: 'Paketin yolda.\nAklın onda kalmasın.', description: 'Kuryenin konumunu haritada takip et. Alım ve teslimat, tarafların onayıyla kayıt altına alınsın.', tag: 'Adım adım takip', detail: 'Karşılıklı teslimat onayı', detailIcon: PhCheckCircle },
  { label: 'Ödeme aktarılsın', icon: PhWallet, eyebrow: 'TESLİMAT TAMAM. SIRA ÖDEMEDE.', title: 'Paket sana.\nÖdeme kuryene.', description: 'Teslimat doğrulandığında akıllı sözleşme ödemeyi serbest bırakır. Kurye, tamamladığı işin karşılığını alır.', tag: 'Otomatik ödeme', detail: 'Teslimat sonrası aktarım', detailIcon: PhShieldCheck },
  { label: 'Puanını ver', icon: PhTrophy, eyebrow: 'İYİ TESLİMATIN BİR KARŞILIĞI VAR', title: 'Bir puan bırak.\nGüven büyüsün.', description: 'Deneyimini değerlendir. Kurye puanları ve liderlik tablosu güncellensin; bir sonraki seçim herkes için kolaylaşsın.', tag: 'Güven birlikte büyür', detail: 'Topluluğun değerlendirmesi', detailIcon: PhStar },
]
const section = ref<HTMLElement | null>(null)
const rail = ref<HTMLElement | null>(null)
const pin = ref<HTMLElement | null>(null)
const { activeStep, progress, paused, reducedMotion, scrollDriven, playing, visible, selectStep, togglePlayback } = useDeliveryJourney(rail, pin, steps.length)
const current = computed(() => steps[activeStep.value]!)

// Hide the sticky navbar while the pinned journey panel fills the screen, so
// nothing overlaps the full-screen scene — restore it once scrolled past.
const navbarHidden = useNavbarVisibility()
watch([visible, scrollDriven], ([isVisible, isScrollDriven]) => {
  navbarHidden.value = isVisible && isScrollDriven
})
onUnmounted(() => {
  navbarHidden.value = false
})

function navigateSteps(event: KeyboardEvent) {
  const focusedIndex = Number((event.target as HTMLElement).closest('[role=tab]')?.id.replace('journey-tab-', '') ?? activeStep.value)
  const keys: Record<string, number> = { ArrowRight: focusedIndex + 1, ArrowLeft: focusedIndex - 1, Home: 0, End: steps.length - 1 }
  if (!(event.key in keys)) return
  event.preventDefault()
  const target = (keys[event.key]! + steps.length) % steps.length
  selectStep(target)
  section.value?.querySelector<HTMLButtonElement>(`#journey-tab-${target}`)?.focus({ preventScroll: true })
}
</script>

<template>
  <section id="how-it-works" ref="section" class="journey-section" :class="{ 'is-scroll-driven': scrollDriven }" aria-labelledby="journey-heading">
    <div class="journey-container">
      <header class="journey-heading">
        <div>
          <p class="journey-kicker"><span /> NASIL ÇALIŞIR?</p>
          <h2 id="journey-heading">Bir paket.<br class="sm:hidden" /> Altı adım. <span>Tam güven.</span></h2>
        </div>
        <p>İlk talepten son onaya kadar,<br />teslimatın her adımı senin kontrolünde.</p>
      </header>

    </div>

    <div ref="rail" class="journey-scroll-rail">
      <div ref="pin" class="journey-pin">
      <div class="journey-experience" :class="{ 'is-playing': playing }">
        <div class="journey-topline">
          <span><ph-cube weight="duotone" /> TESLİMATIN YOLCULUĞU</span>
          <span class="journey-demo">Etkileşimli demo <span class="journey-status-dot" /></span>
        </div>

        <div id="journey-panel" class="journey-panel" role="tabpanel" :aria-labelledby="`journey-tab-${activeStep}`" tabindex="0">
          <delivery-journey-scene :step="activeStep" :playing="playing" :reduced-motion="reducedMotion" />
          <div class="journey-copy">
            <div class="journey-chapter"><span>ADIM {{ String(activeStep + 1).padStart(2, '0') }}</span><span>/ 06</span></div>
            <transition name="journey-copy" mode="out-in">
              <div :key="activeStep" class="journey-copy-content">
                <p class="journey-eyebrow">{{ current.eyebrow }}</p>
                <h3>{{ current.title }}</h3>
                <p class="journey-description">{{ current.description }}</p>
                <div class="journey-assurance"><component :is="current.detailIcon" weight="duotone" /><span>{{ current.detail }}</span></div>
              </div>
            </transition>
            <div class="journey-controls">
              <span class="journey-tag"><ph-check weight="bold" /> {{ current.tag }}</span>
              <div class="journey-arrows">
                <button type="button" aria-label="Önceki adım" :disabled="activeStep === 0" @click="selectStep(activeStep - 1)"><ph-arrow-left /></button>
                <button type="button" aria-label="Sonraki adım" :disabled="activeStep === steps.length - 1" @click="selectStep(activeStep + 1)"><ph-arrow-right /></button>
              </div>
            </div>
          </div>
        </div>

        <div class="journey-timeline" role="tablist" aria-label="Teslimat adımları" @keydown="navigateSteps">
          <button
            v-for="(step, index) in steps" :id="`journey-tab-${index}`" :key="step.label"
            type="button" role="tab" :aria-label="`Adım ${index + 1}: ${step.label}`" :aria-selected="activeStep === index" aria-controls="journey-panel"
            :tabindex="activeStep === index ? 0 : -1" class="journey-stop"
            :class="{ 'is-active': activeStep === index, 'is-complete': activeStep > index }"
            :style="{ '--step-progress': activeStep > index ? 1 : activeStep === index ? progress : 0 }"
            @click="selectStep(index)"
          >
            <span class="journey-stop-track"><span /></span>
            <span class="journey-stop-top"><span class="journey-stop-icon"><component :is="activeStep > index ? PhCheck : step.icon" weight="duotone" /></span><span class="journey-stop-number">{{ String(index + 1).padStart(2, '0') }}</span></span>
            <span class="journey-stop-label">{{ step.label }}</span>
          </button>
        </div>
        <footer class="journey-footer">
          <span><ph-arrow-down /> {{ scrollDriven ? 'Yolculuğu keşfetmek için kaydır.' : 'Adımlara dokun, yolculuğu keşfet.' }}</span>
          <button v-if="!reducedMotion" type="button" :aria-label="paused ? 'Sahne animasyonlarını başlat' : 'Sahne animasyonlarını duraklat'" @click="togglePlayback">
            <ph-play v-if="paused" weight="fill" /><ph-pause v-else weight="fill" />
            {{ paused ? 'Animasyonları aç' : 'Animasyonları duraklat' }}
          </button>
          <span v-else>Animasyonlar azaltıldı</span>
        </footer>
      </div>
      </div>
    </div>
    <div class="journey-container">
      <div class="journey-bottom-note"><ph-shield-check weight="duotone" /><span>Her adımda şeffaflık. Her teslimatta güven.</span><span class="journey-powered">MONAD ÜZERİNDE</span></div>
    </div>
  </section>
</template>
