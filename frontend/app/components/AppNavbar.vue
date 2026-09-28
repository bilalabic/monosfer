<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { PhArrowUpRight, PhList, PhMapPin, PhNavigationArrow, PhPackage, PhPath, PhPlus, PhSignOut, PhTrophy, PhUser, PhX } from '@phosphor-icons/vue'
import { useWalletStore } from '@/stores/useWalletStore'
import { useNavbarVisibility } from '@/composables/useNavbarVisibility'

const wallet = useWalletStore()
const router = useRouter()
const route = useRoute()
const mobileOpen = ref(false)
const header = ref<HTMLElement | null>(null)
const menuToggle = ref<HTMLButtonElement | null>(null)
const navbarHidden = useNavbarVisibility()

const navLinks = [
  { to: '/deliveries', label: 'Teslimatlar', description: 'Yola çıkacak paketleri keşfet', icon: PhPackage },
  { to: '/couriers', label: 'Kuryeler', description: 'Teslimat ağıyla tanış', icon: PhTrophy },
  { to: '/map', label: 'Harita', description: 'Yakınındaki teslimatları gör', icon: PhMapPin },
]
const authLinks = [
  { to: '/kuryem-nerede', label: 'Kuryem Nerede', description: 'Teslimatının durumunu takip et', icon: PhNavigationArrow },
  { to: '/dashboard', label: 'Panel', description: 'Tüm işlemlerin tek yerde', icon: PhUser },
]
const guideLink = { to: '/#how-it-works', label: 'Nasıl çalışır?', description: 'Altı adımda teslimat yolculuğu', icon: PhPath }
const visibleNavLinks = computed(() => [...navLinks, ...(wallet.connected ? authLinks : [guideLink])])
const accountName = computed(() => wallet.userProfile.name || wallet.displayAddress())

function isActive(to: string) {
  return to.includes('#') ? route.fullPath === to : route.path === to || route.path.startsWith(`${to}/`)
}
function closeMenu(restoreFocus = false) {
  mobileOpen.value = false
  if (restoreFocus) menuToggle.value?.focus()
}
function onOutsidePointer(event: PointerEvent) {
  if (mobileOpen.value && event.target instanceof Node && !header.value?.contains(event.target)) closeMenu()
}
function onFocusOut(event: FocusEvent) {
  if (event.relatedTarget instanceof Node && !header.value?.contains(event.relatedTarget)) closeMenu()
}
async function handleDisconnect() {
  closeMenu()
  await wallet.disconnect()
  await router.push('/')
}
watch(() => route.fullPath, () => closeMenu())
watch(navbarHidden, hidden => { if (hidden) closeMenu() })
onMounted(() => document.addEventListener('pointerdown', onOutsidePointer))
onUnmounted(() => document.removeEventListener('pointerdown', onOutsidePointer))
</script>

<template>
  <header
    ref="header" class="site-header" :class="{ 'is-hidden': navbarHidden, 'has-session': wallet.connected, 'is-menu-open': mobileOpen }"
    :inert="navbarHidden" @keydown.esc="closeMenu(true)" @focusout="onFocusOut"
  >
    <div class="site-nav">
      <nuxt-link to="/" class="site-brand" aria-label="Delivera ana sayfa" @click="closeMenu()">
        <span class="site-brand-mark"><img src="/gemini-svg-_1_.png" alt="" width="38" height="38"></span>
        <span class="site-brand-name">Delivera<span>.</span></span>
      </nuxt-link>

      <nav class="site-nav-links" aria-label="Ana gezinme">
        <nuxt-link
          v-for="link in visibleNavLinks" :key="link.to" :to="link.to"
          class="site-nav-link" :class="{ 'is-active': isActive(link.to) }" :aria-current="isActive(link.to) ? 'page' : undefined"
        >
          <component :is="link.icon" weight="duotone" aria-hidden="true" />
          <span>{{ link.label }}</span>
        </nuxt-link>
      </nav>

      <div class="site-nav-actions">
        <template v-if="!wallet.connected">
          <nuxt-link to="/login" class="site-nav-login">Giriş yap</nuxt-link>
          <nuxt-link to="/register" class="site-nav-cta">Kayıt ol <ph-arrow-up-right weight="bold" aria-hidden="true" /></nuxt-link>
        </template>
        <template v-else>
          <nuxt-link to="/create" class="site-nav-cta site-nav-create"><ph-plus weight="bold" aria-hidden="true" /> Teslimat oluştur</nuxt-link>
          <div class="site-account">
            <nuxt-link to="/dashboard" class="site-account-profile" :aria-label="`${accountName}, hesabımı aç`">
              <span class="site-account-avatar"><ph-user weight="duotone" aria-hidden="true" /><i /></span>
              <span class="site-account-info"><strong>{{ accountName }}</strong><small>{{ wallet.balance }} MON</small></span>
            </nuxt-link>
            <button type="button" class="site-account-exit" aria-label="Oturumu kapat" @click="handleDisconnect"><ph-sign-out aria-hidden="true" /></button>
          </div>
        </template>
        <button
          ref="menuToggle" type="button" class="site-menu-toggle" :aria-expanded="mobileOpen" aria-controls="site-mobile-menu"
          :aria-label="mobileOpen ? 'Menüyü kapat' : 'Menüyü aç'" @click="mobileOpen = !mobileOpen"
        >
          <ph-x v-if="mobileOpen" weight="bold" aria-hidden="true" /><ph-list v-else weight="bold" aria-hidden="true" />
        </button>
      </div>
    </div>

    <transition name="site-menu">
      <div v-if="mobileOpen" id="site-mobile-menu" class="site-mobile-menu">
        <div class="site-menu-heading"><span>KEŞFET</span><span>Bir paketle başlar.</span></div>
        <nav aria-label="Mobil gezinme" class="site-mobile-links">
          <nuxt-link
            v-for="link in visibleNavLinks" :key="link.to" :to="link.to" class="site-mobile-link"
            :class="{ 'is-active': isActive(link.to) }" :aria-current="isActive(link.to) ? 'page' : undefined" @click="closeMenu()"
          >
            <span class="site-mobile-icon"><component :is="link.icon" weight="duotone" aria-hidden="true" /></span>
            <span><strong>{{ link.label }}</strong><small>{{ link.description }}</small></span>
            <ph-arrow-up-right class="site-mobile-arrow" aria-hidden="true" />
          </nuxt-link>
        </nav>
        <div class="site-menu-footer">
          <span><strong>{{ wallet.connected ? 'Yeni bir yolculuk başlat.' : 'Paketin güvenle yola çıksın.' }}</strong><small>Her adımda kontrol sende.</small></span>
          <nuxt-link :to="wallet.connected ? '/create' : '/register'" class="site-nav-cta" @click="closeMenu()">
            {{ wallet.connected ? 'Oluştur' : 'Başla' }} <ph-arrow-up-right weight="bold" aria-hidden="true" />
          </nuxt-link>
        </div>
        <nuxt-link v-if="!wallet.connected" to="/login" class="site-mobile-login" @click="closeMenu()">Zaten hesabın var mı? <strong>Giriş yap <ph-arrow-up-right aria-hidden="true" /></strong></nuxt-link>
      </div>
    </transition>
  </header>
</template>
