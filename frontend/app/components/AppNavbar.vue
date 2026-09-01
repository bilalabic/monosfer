<script setup lang="ts">
import { ref, computed } from 'vue'
import { PhPackage as Package, PhTrophy as Trophy, PhPlus as Plus, PhSignOut as LogOut, PhList as Menu, PhX as X, PhUser as User, PhMapPin as MapPin, PhNavigationArrow as Navigation } from '@phosphor-icons/vue'
import { useWalletStore } from '@/stores/useWalletStore'

const wallet = useWalletStore()
const router = useRouter()
const mobileOpen = ref(false)

const navLinks = [
  { to: '/deliveries', label: 'Teslimatlar', icon: Package },
  { to: '/couriers', label: 'Kuryeler', icon: Trophy },
  { to: '/map', label: 'Harita', icon: MapPin },
]

const authLinks = [
  { to: '/kuryem-nerede', label: 'Kuryem Nerede', icon: Navigation },
  { to: '/dashboard', label: 'Panel', icon: User },
]

const visibleNavLinks = computed(() => wallet.connected ? [...navLinks, ...authLinks] : navLinks)

function handleCreate() {
  mobileOpen.value = false
  router.push('/create')
}
</script>

<template>
  <header class="sticky top-0 z-50 w-full bg-white/90 backdrop-blur-md border-b border-stone-200">
    <div class="mx-auto flex max-w-6xl items-center justify-between px-5 py-3.5 sm:px-8">
      <!-- Logo -->
      <NuxtLink to="/" class="flex items-center gap-2.5 group" @click="mobileOpen = false">
        <img
          src="/gemini-svg-_1_.png"
          alt="Delivera"
          class="size-8 rounded-xl object-cover shadow-sm transition-transform group-hover:scale-105"
        >
        <span class="text-lg font-bold tracking-tight text-stone-900">Delivera</span>
      </NuxtLink>

      <!-- Desktop Nav -->
      <nav class="hidden items-center gap-0.5 md:flex">
        <NuxtLink
          v-for="link in visibleNavLinks"
          :key="link.to"
          :to="link.to"
          class="flex items-center gap-1.5 rounded-lg px-3.5 py-2 text-sm font-medium text-stone-500 transition-all hover:bg-stone-100 hover:text-stone-900"
          active-class="bg-stone-100 text-stone-900"
        >
          <component :is="link.icon" class="size-4" weight="bold" />
          {{ link.label }}
        </NuxtLink>
      </nav>

      <!-- Actions -->
      <div class="flex items-center gap-2.5">
        <button
          v-if="wallet.connected"
          class="hidden btn-primary md:flex"
          @click="handleCreate"
        >
          <Plus class="size-4" weight="bold" />
          Teslimat Oluştur
        </button>

        <div v-if="!wallet.connected" class="hidden sm:flex items-center gap-2">
          <NuxtLink to="/login" class="text-sm font-medium text-stone-600 hover:text-stone-900 px-2 py-2 transition">
            Giriş Yap
          </NuxtLink>
          <NuxtLink to="/register" class="rounded-lg border border-orange-200 bg-orange-50 px-3.5 py-2 text-sm font-medium text-orange-700 shadow-sm transition hover:bg-orange-100 hover:border-orange-300">
            Kayıt Ol
          </NuxtLink>
        </div>

        <div v-else class="flex items-center gap-2 rounded-lg border border-stone-200 bg-white px-3 py-1.5 shadow-sm hover:bg-stone-50 transition cursor-pointer" @click="router.push('/dashboard')">
          <span class="size-2 rounded-full bg-green-500 animate-pulse-dot" />
          <span class="hidden text-sm font-medium text-stone-700 sm:inline">{{ wallet.userProfile.name || wallet.displayAddress() }}</span>
          <span class="text-sm font-semibold text-orange-600">{{ wallet.balance }} MON</span>
          <button class="ml-1 rounded p-0.5 text-stone-400 hover:text-stone-700 hover:bg-stone-200 transition" @click.stop="wallet.disconnect(); router.push('/')">
            <LogOut class="size-3.5" />
          </button>
        </div>

        <button
          class="flex size-9 items-center justify-center rounded-lg border border-stone-200 bg-white md:hidden"
          @click="mobileOpen = !mobileOpen"
        >
          <Menu v-if="!mobileOpen" class="size-4 text-stone-600" />
          <X v-else class="size-4 text-stone-600" />
        </button>
      </div>
    </div>

    <!-- Mobile Menu -->
    <Transition
      enter-active-class="transition-all duration-200"
      enter-from-class="opacity-0 -translate-y-1"
      enter-to-class="opacity-100 translate-y-0"
      leave-active-class="transition-all duration-150"
      leave-from-class="opacity-100 translate-y-0"
      leave-to-class="opacity-0 -translate-y-1"
    >
      <div v-if="mobileOpen" class="border-t border-stone-100 bg-white px-5 py-3 md:hidden">
        <nav class="flex flex-col gap-1">
          <NuxtLink
            v-for="link in visibleNavLinks"
            :key="link.to"
            :to="link.to"
            class="flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium text-stone-600 transition hover:bg-stone-50 hover:text-stone-900"
            active-class="bg-stone-100 text-stone-900"
            @click="mobileOpen = false"
          >
            <component :is="link.icon" class="size-4" weight="bold" />
            {{ link.label }}
          </NuxtLink>
          <div v-if="!wallet.connected" class="mt-2 grid grid-cols-2 gap-2">
            <NuxtLink to="/login" class="flex justify-center rounded-lg border border-stone-200 bg-white px-3 py-2.5 text-sm font-medium text-stone-700 transition hover:bg-stone-50" @click="mobileOpen = false">
              Giriş Yap
            </NuxtLink>
            <NuxtLink to="/register" class="flex justify-center rounded-lg border border-orange-200 bg-orange-50 px-3 py-2.5 text-sm font-medium text-orange-700 transition hover:bg-orange-100" @click="mobileOpen = false">
              Kayıt Ol
            </NuxtLink>
          </div>
          <button v-if="wallet.connected" class="mt-2 btn-primary w-full justify-center" @click="handleCreate">
            <Plus class="size-4" weight="bold" />
            Teslimat Oluştur
          </button>
        </nav>
      </div>
    </Transition>
  </header>
</template>
