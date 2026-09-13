<script setup lang="ts">
import { PhArrowUpRight, PhBicycle, PhCheck, PhCheckCircle, PhCoins, PhLockKey, PhMapPin, PhPackage, PhQrCode, PhShieldCheck, PhStar, PhTrophy, PhWallet } from '@phosphor-icons/vue'

defineProps<{ step: number; playing: boolean; reducedMotion: boolean }>()
const bids = [
  { name: 'Kurye A', price: '12', rating: '4.8' },
  { name: 'Kurye B', price: '9', rating: '4.9' },
  { name: 'Kurye C', price: '15', rating: '4.7' },
]
</script>

<template>
  <div class="journey-scene" :class="{ 'is-playing': playing, 'is-reduced': reducedMotion }" :data-step="step" aria-hidden="true">
    <div class="journey-scene-glow" />
    <div class="journey-orbit journey-orbit--outer" />
    <div class="journey-orbit journey-orbit--inner" />
    <div class="journey-scene-grid" />
    <div class="journey-platform"><div /><div /><div /></div>
    <span class="journey-scene-coordinate">{{ String(step + 1).padStart(2, '0') }} / 06 <span>—</span> MONAD NETWORK</span>

    <transition name="journey-object" mode="out-in">
      <div :key="step" class="journey-scene-content">
        <template v-if="step === 0">
          <div class="journey-package-float">
            <div class="journey-package">
              <div class="journey-package-face journey-package-front"><span class="journey-package-label"><ph-package weight="duotone" /><i /><i /><i /><small>HANDLE WITH CARE</small></span></div>
              <div class="journey-package-face journey-package-back" />
              <div class="journey-package-face journey-package-right"><ph-arrow-up-right weight="bold" /></div>
              <div class="journey-package-face journey-package-left" />
              <div class="journey-package-face journey-package-top"><span /></div>
              <div class="journey-package-face journey-package-bottom" />
            </div>
          </div>
          <div class="journey-float-card journey-float-card--upper"><span class="journey-card-icon"><ph-map-pin weight="fill" /></span><div><small>YENİ TESLİMAT</small><strong>Bir yolculuk başlıyor.</strong></div></div>
          <div class="journey-float-card journey-float-card--lower"><span class="journey-card-icon journey-card-icon--green"><ph-lock-key weight="fill" /></span><div><small>AKILLI SÖZLEŞME</small><strong>Ödemen koruma altında</strong></div><span class="journey-mini-check"><ph-check weight="bold" /></span></div>
        </template>

        <template v-else-if="step === 1">
          <div class="journey-feed">
            <div class="journey-feed-header"><span class="journey-live-dot" /> CANLI TEKLİFLER <span class="journey-feed-count">{{ bids.length }}</span></div>
            <div v-for="(bid, index) in bids" :key="bid.name" class="journey-feed-row" :class="{ 'is-lowest': index === 1 }" :style="{ '--row-index': index }">
              <div class="journey-feed-avatar"><ph-bicycle weight="duotone" /></div>
              <div class="journey-feed-info">
                <strong>{{ bid.name }}</strong>
                <span class="journey-feed-rating"><ph-star weight="fill" /> {{ bid.rating }}</span>
              </div>
              <div class="journey-feed-price">{{ bid.price }} <small>MON</small></div>
              <span v-if="index === 1" class="journey-feed-tag">EN DÜŞÜK</span>
            </div>
          </div>
          <div class="journey-float-card journey-float-card--bottom"><span class="journey-card-icon"><ph-coins weight="fill" /></span><div><small>REKABETÇİ TEKLİFLER</small><strong>Senin paketin. Onların teklifi.</strong></div></div>
        </template>

        <template v-else-if="step === 2">
          <div class="journey-bids has-selection">
            <div v-for="(bid, index) in bids" :key="bid.name" class="journey-bid" :class="{ 'is-selected': index === 1 }" :style="{ '--bid-index': index }">
              <span v-if="index === 1" class="journey-bid-badge">SEÇİLEN KURYE</span>
              <div class="journey-courier-avatar"><ph-bicycle weight="duotone" /></div>
              <strong>{{ bid.name }}</strong><span class="journey-bid-rating"><ph-star weight="fill" /> {{ bid.rating }}</span>
              <div class="journey-bid-price">{{ bid.price }} <small>MON</small></div>
              <span class="journey-bid-security"><ph-shield-check weight="fill" /> Teminatlı</span>
              <span v-if="index === 1" class="journey-selected-check"><ph-check weight="bold" /></span>
            </div>
          </div>
          <div class="journey-float-card journey-float-card--bottom"><span class="journey-card-icon"><ph-check-circle weight="fill" /></span><div><small>EŞLEŞME TAMAMLANDI</small><strong>Paketin emin ellerde.</strong></div></div>
        </template>

        <template v-else-if="step === 3">
          <div class="journey-map">
            <svg viewBox="0 0 440 270" fill="none">
              <path class="journey-map-street" d="M0 65H440M0 135H440M0 205H440M75 0V270M150 0V270M225 0V270M300 0V270M375 0V270" />
              <path class="journey-map-block" d="M90 80H135V120H90zM240 150H285V190H240zM315 80H360V120H315zM165 10H210V50H165zM15 150H60V190H15zM315 220H360V260H315z" />
              <path class="journey-map-route-base" d="M75 205H150V135H300V65H375" />
              <path class="journey-map-route" d="M75 205H150V135H300V65H375" pathLength="1" />
              <circle cx="75" cy="205" r="8" class="journey-map-origin" /><circle cx="375" cy="65" r="12" class="journey-map-destination" /><circle cx="375" cy="65" r="5" fill="currentColor" />
            </svg>
            <span class="journey-map-label journey-map-label--start">ALIM</span><span class="journey-map-label journey-map-label--end">TESLİMAT</span>
            <div class="journey-map-courier"><ph-bicycle weight="fill" /></div>
          </div>
          <div class="journey-float-card journey-float-card--upper"><span class="journey-card-icon"><ph-bicycle weight="fill" /></span><div><small>TESLİMAT DURUMU</small><strong>Paketin sana geliyor.</strong></div><span class="journey-status-dot" /></div>
          <div class="journey-float-card journey-float-card--bottom"><span class="journey-card-icon journey-card-icon--green"><ph-check-circle weight="fill" /></span><div><small>HER ADIM KAYIT ALTINDA</small><strong>Alındı → Yolda → Teslim edildi</strong></div></div>
        </template>

        <template v-else-if="step === 4">
          <div class="journey-payment">
            <div class="journey-phone">
              <div class="journey-phone-notch" />
              <div class="journey-phone-screen">
                <span class="journey-phone-label">TESLİMAT ONAYI</span>
                <div class="journey-qr"><ph-qr-code weight="fill" /><span class="journey-qr-scan" /></div>
                <span class="journey-phone-status"><ph-check-circle weight="fill" /> Doğrulandı</span>
              </div>
              <span class="journey-mini-check journey-phone-check"><ph-check weight="bold" /></span>
            </div>
            <div class="journey-wallet"><ph-wallet weight="duotone" /><span>KURYE CÜZDANI</span><strong>+9 <small>MON</small></strong><span class="journey-wallet-success"><ph-check-circle weight="fill" /> Aktarım tamamlandı</span></div>
            <span v-for="coin in 5" :key="coin" class="journey-transfer-coin" :style="{ '--coin-index': coin }"><img src="/monad-coin.svg" alt=""></span>
          </div>
          <div class="journey-float-card journey-float-card--bottom"><span class="journey-card-icon journey-card-icon--green"><ph-check weight="bold" /></span><div><small>YERİNE ULAŞAN SADECE PAKET DEĞİL</small><strong>Emeğin karşılığı da yerini buldu.</strong></div></div>
        </template>

        <template v-else>
          <div class="journey-award">
            <div class="journey-award-halo" /><div class="journey-trophy"><ph-trophy weight="duotone" /></div>
            <div class="journey-podium"><span>01</span></div>
            <div class="journey-rating"><ph-star v-for="star in 5" :key="star" weight="fill" :style="{ '--star-index': star }" /></div>
            <span v-for="particle in 8" :key="particle" class="journey-confetti" :style="{ '--particle-index': particle }" />
          </div>
          <div class="journey-float-card journey-float-card--upper"><span class="journey-card-icon"><ph-star weight="fill" /></span><div><small>İYİ BİR DENEYİM, KALICI BİR İZ</small><strong>Bir sonraki teslimata güven.</strong></div></div>
          <div class="journey-float-card journey-float-card--bottom"><span class="journey-card-icon journey-card-icon--green"><ph-trophy weight="fill" /></span><div><small>LİDERLİK TABLOSU</small><strong>İyi kuryeler öne çıksın.</strong></div><ph-arrow-up-right /></div>
        </template>
      </div>
    </transition>
    <span class="journey-scene-caption">Süreç görselleştirmesi · Örnek veriler</span>
  </div>
</template>
