<script setup lang="ts">
import { PhArrowUpRight, PhPackage } from '@phosphor-icons/vue'

const linkGroups = [
  {
    title: 'Keşfet',
    links: [
      { to: '/deliveries', label: 'Teslimatlar' },
      { to: '/couriers', label: 'Kuryeler' },
      { to: '/map', label: 'Teslimat haritası' },
    ],
  },
  {
    title: 'Başlarken',
    links: [
      { to: '/#how-it-works', label: 'Nasıl çalışır?' },
      { to: '/#security', label: 'Güvenlik' },
      { to: '/register', label: 'Hesap oluştur' },
      { to: '/login', label: 'Giriş yap' },
      { to: '/support', label: 'Destek' },
    ],
  },
]
const year = new Date().getFullYear()
</script>

<template>
  <footer class="site-footer" aria-label="Site alt bilgisi">
    <div class="footer-surface">
      <div class="footer-content">
        <div class="footer-main">
          <div class="footer-intro">
            <nuxt-link to="/" class="footer-brand" aria-label="Delivera ana sayfa">
              <img src="/gemini-svg-_1_.png" alt="" width="36" height="36">
              <span>Delivera<span>.</span></span>
            </nuxt-link>
            <p class="footer-statement">Her teslimatta,<br>birbirimize <span>daha yakın.</span></p>
            <p class="footer-description">Yolları birleştiren, güveni paylaşan<br>merkeziyetsiz teslimat ağı.</p>
            <nuxt-link to="/create" class="footer-start">Bir teslimat başlat <span><ph-arrow-up-right weight="bold" aria-hidden="true" /></span></nuxt-link>
          </div>

          <nav v-for="group in linkGroups" :key="group.title" class="footer-links" :aria-label="`Alt menü: ${group.title}`">
            <h2>{{ group.title }}</h2>
            <ul>
              <li v-for="link in group.links" :key="link.to">
                <nuxt-link :to="link.to">{{ link.label }}<ph-arrow-up-right aria-hidden="true" /></nuxt-link>
              </li>
            </ul>
          </nav>
        </div>

        <div class="footer-signature" aria-hidden="true">
          <span class="footer-wordmark">Delivera<span>.</span></span>
          <div class="footer-route">
            <span class="footer-route-label">BİR PAKET. BİNLERCE OLASILIK.</span>
            <svg viewBox="0 0 360 100" fill="none">
              <path class="footer-route-guide" d="M14 70H346" />
              <path class="footer-route-line" d="M14 70H74C122 70 110 20 164 20H201C243 20 227 70 278 70H346" />
              <circle cx="14" cy="70" r="5" /><circle cx="346" cy="70" r="9" class="footer-route-destination" /><circle cx="346" cy="70" r="3" />
            </svg>
            <span class="footer-route-package"><ph-package weight="duotone" /></span>
          </div>
        </div>

        <div class="footer-bottom">
          <p>© {{ year }} Delivera <span>·</span> Monad Hackathon</p>
          <a href="https://monad.xyz" target="_blank" rel="noopener noreferrer" class="footer-network" aria-label="Monad üzerinde geliştirildi — Monad sitesini yeni sekmede aç">
            <span class="footer-network-dot" /> Monad üzerinde geliştirildi <ph-arrow-up-right aria-hidden="true" />
          </a>
        </div>
      </div>
    </div>
  </footer>
</template>
