<script setup lang="ts">
import { useRouter } from 'vue-router'
import { PhArrowRight, PhWarning } from '@phosphor-icons/vue'
import { useWalletStore } from '@/stores/useWalletStore'
import { useMetaMask } from '@/composables/useMetaMask'

const router = useRouter()
const mm = useMetaMask()
const wallet = useWalletStore()

async function handleMetaMask() {
  const result = await mm.connect()
  if (!result) return
  await wallet.connectMetaMask(result.address)
  router.push('/dashboard')
}

</script>

<template>
  <div class="flex min-h-[80vh] items-center justify-center px-5 py-12 sm:px-8">
    <div class="w-full max-w-sm">

      <!-- Logo & title -->
      <div class="mb-8 text-center">
        <div class="mx-auto mb-4 flex size-14 items-center justify-center rounded-2xl bg-orange-500 shadow-lg">
          <svg class="size-8 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
            <path stroke-linecap="round" stroke-linejoin="round" d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10"/>
          </svg>
        </div>
        <h1 class="text-2xl font-bold text-stone-900">Delivera'ya Giriş</h1>
        <p class="mt-2 text-sm text-stone-500">Cüzdanınızla bağlanın, kimliğinizi kanıtlayın</p>
      </div>

      <!-- MetaMask Card -->
      <div class="card rounded-2xl bg-white p-6 shadow-sm">

        <!-- MetaMask not installed -->
        <div v-if="!mm.isInstalled.value" class="mb-5 rounded-xl border border-amber-200 bg-amber-50 p-4">
          <div class="flex items-start gap-3">
            <PhWarning class="mt-0.5 size-4 shrink-0 text-amber-600" weight="fill" />
            <div>
              <p class="text-sm font-semibold text-amber-800">MetaMask bulunamadı</p>
              <p class="mt-0.5 text-xs text-amber-700">
                Giriş yapmak için tarayıcı eklentisini yükleyin.
              </p>
              <a
                href="https://metamask.io/download/"
                target="_blank"
                rel="noopener noreferrer"
                class="mt-2 inline-flex items-center gap-1 text-xs font-semibold text-amber-700 underline underline-offset-2 hover:text-amber-900"
              >
                MetaMask İndir →
              </a>
            </div>
          </div>
        </div>

        <!-- Error messages -->
        <div v-if="mm.error.value === 'user_rejected'" class="mb-5 rounded-xl border border-red-200 bg-red-50 p-3 text-xs text-red-700">
          İstek reddedildi. MetaMask'ta onaylamanız gerekiyor.
        </div>
        <div v-else-if="mm.error.value === 'unknown'" class="mb-5 rounded-xl border border-red-200 bg-red-50 p-3 text-xs text-red-700">
          Bağlantı hatası oluştu. Tekrar deneyin.
        </div>

        <!-- MetaMask connect button -->
        <button
          class="group relative flex w-full items-center justify-center gap-3 overflow-hidden rounded-xl px-5 py-4 font-semibold text-white transition-all disabled:opacity-60"
          :class="mm.isInstalled.value ? 'bg-[#F6851B] hover:bg-[#E2761B] shadow-md hover:shadow-lg' : 'bg-stone-300 cursor-not-allowed'"
          :disabled="mm.connecting.value || !mm.isInstalled.value"
          @click="handleMetaMask"
        >
          <!-- MetaMask Fox SVG -->
          <svg class="size-6 shrink-0" viewBox="0 0 318.6 318.6" xmlns="http://www.w3.org/2000/svg">
            <polygon fill="#E2761B" stroke="#E2761B" stroke-linecap="round" stroke-linejoin="round" points="274.1,35.5 174.6,109.4 193,65.8"/>
            <polygon fill="#E4761B" stroke="#E4761B" stroke-linecap="round" stroke-linejoin="round" points="44.4,35.5 143.1,110.1 125.6,65.8"/>
            <polygon fill="#D7C1B3" stroke="#D7C1B3" stroke-linecap="round" stroke-linejoin="round" points="238.3,206.8 211.8,247.4 268.5,263 284.8,207.7"/>
            <polygon fill="#D7C1B3" stroke="#D7C1B3" stroke-linecap="round" stroke-linejoin="round" points="33.9,207.7 50.1,263 106.8,247.4 80.3,206.8"/>
            <polygon fill="#D7C1B3" stroke="#D7C1B3" stroke-linecap="round" stroke-linejoin="round" points="103.6,138.2 87.8,162.1 144.1,164.6 142.1,104.1"/>
            <polygon fill="#D7C1B3" stroke="#D7C1B3" stroke-linecap="round" stroke-linejoin="round" points="214.9,138.2 175.9,103.4 174.6,164.6 230.8,162.1"/>
            <polygon fill="#233447" stroke="#233447" stroke-linecap="round" stroke-linejoin="round" points="106.8,247.4 140.6,230.9 111.4,208.1"/>
            <polygon fill="#233447" stroke="#233447" stroke-linecap="round" stroke-linejoin="round" points="177.9,230.9 211.8,247.4 207.1,208.1"/>
            <polygon fill="#CD6116" stroke="#CD6116" stroke-linecap="round" stroke-linejoin="round" points="211.8,247.4 177.9,230.9 180.6,253 180.3,262.3"/>
            <polygon fill="#CD6116" stroke="#CD6116" stroke-linecap="round" stroke-linejoin="round" points="106.8,247.4 138.3,262.3 138.1,253 140.6,230.9"/>
            <polygon fill="#E4751F" stroke="#E4751F" stroke-linecap="round" stroke-linejoin="round" points="138.8,193.5 110.6,185.2 130.5,176.1"/>
            <polygon fill="#E4751F" stroke="#E4751F" stroke-linecap="round" stroke-linejoin="round" points="179.7,193.5 187.9,176.1 208,185.2"/>
            <polygon fill="#F6851B" stroke="#F6851B" stroke-linecap="round" stroke-linejoin="round" points="106.8,247.4 111.6,206.8 80.3,207.7"/>
            <polygon fill="#F6851B" stroke="#F6851B" stroke-linecap="round" stroke-linejoin="round" points="207,206.8 211.8,247.4 238.3,207.7"/>
            <polygon fill="#F6851B" stroke="#F6851B" stroke-linecap="round" stroke-linejoin="round" points="230.8,162.1 174.6,164.6 179.8,193.5 188,176.1 208.1,185.2"/>
            <polygon fill="#F6851B" stroke="#F6851B" stroke-linecap="round" stroke-linejoin="round" points="110.6,185.2 130.6,176.1 138.8,193.5 144.1,164.6 87.8,162.1"/>
            <polygon fill="#C0AD9E" stroke="#C0AD9E" stroke-linecap="round" stroke-linejoin="round" points="87.8,162.1 111.4,208.1 110.6,185.2"/>
            <polygon fill="#C0AD9E" stroke="#C0AD9E" stroke-linecap="round" stroke-linejoin="round" points="208.1,185.2 207.1,208.1 230.8,162.1"/>
            <polygon fill="#C0AD9E" stroke="#C0AD9E" stroke-linecap="round" stroke-linejoin="round" points="144.1,164.6 138.8,193.5 145.4,227.6 146.9,182.7"/>
            <polygon fill="#C0AD9E" stroke="#C0AD9E" stroke-linecap="round" stroke-linejoin="round" points="174.6,164.6 171.9,182.6 172.9,227.6 179.8,193.5"/>
            <polygon fill="#161616" stroke="#161616" stroke-linecap="round" stroke-linejoin="round" points="179.8,193.5 172.9,227.6 177.9,230.9 207.1,208.1 208.1,185.2"/>
            <polygon fill="#161616" stroke="#161616" stroke-linecap="round" stroke-linejoin="round" points="110.6,185.2 111.4,208.1 140.6,230.9 145.4,227.6 138.8,193.5"/>
            <polygon fill="#763D16" stroke="#763D16" stroke-linecap="round" stroke-linejoin="round" points="180.3,262.3 180.6,253 178.1,250.8 140.4,250.8 138.1,253 138.3,262.3 106.8,247.4 117.8,256.4 140.1,271.9 178.4,271.9 200.8,256.4 211.8,247.4"/>
            <polygon fill="#F6851B" stroke="#F6851B" stroke-linecap="round" stroke-linejoin="round" points="177.9,230.9 172.9,227.6 145.4,227.6 140.6,230.9 138.1,253 140.4,250.8 178.1,250.8 180.6,253"/>
            <polygon fill="#E2761B" stroke="#E2761B" stroke-linecap="round" stroke-linejoin="round" points="278.3,114.2 286.8,73.4 274.1,35.5 177.9,106.9 214.9,138.2 267.2,153.5 278.8,140 273.8,136.4 281.8,129.1 275.6,124.3 283.6,118.2"/>
            <polygon fill="#E2761B" stroke="#E2761B" stroke-linecap="round" stroke-linejoin="round" points="31.8,73.4 40.3,114.2 34.9,118.2 42.9,124.3 36.8,129.1 44.8,136.4 39.8,140 51.3,153.5 103.6,138.2 140.6,106.9 44.4,35.5"/>
            <polygon fill="#F6851B" stroke="#F6851B" stroke-linecap="round" stroke-linejoin="round" points="267.2,153.5 214.9,138.2 230.8,162.1 207.1,208.1 238.3,207.7 284.8,207.7"/>
            <polygon fill="#F6851B" stroke="#F6851B" stroke-linecap="round" stroke-linejoin="round" points="103.6,138.2 51.3,153.5 33.9,207.7 80.3,207.7 111.4,208.1 87.8,162.1"/>
            <polygon fill="#F6851B" stroke="#F6851B" stroke-linecap="round" stroke-linejoin="round" points="174.6,164.6 177.9,106.9 193.1,65.8 125.6,65.8 140.6,106.9 144.1,164.6 145.3,182.8 145.4,227.6 172.9,227.6 173.1,182.8"/>
          </svg>

          <span v-if="mm.connecting.value" class="flex items-center gap-2">
            <svg class="size-4 animate-spin" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"/>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/>
            </svg>
            Bağlanıyor...
          </span>
          <span v-else>MetaMask ile Bağlan</span>
          <PhArrowRight v-if="!mm.connecting.value" class="size-4 transition group-hover:translate-x-0.5" weight="bold" />
        </button>

        <!-- Monad badge -->
        <div class="mt-4 flex items-center justify-center gap-2 text-xs text-stone-400">
          <span class="inline-block size-1.5 rounded-full bg-purple-400"></span>
          Monad Testnet · 10,000 TPS · 400ms blok süresi
        </div>

        <!-- How it works -->
        <div class="mt-5 rounded-xl border border-stone-100 bg-stone-50 p-4 space-y-2">
          <p class="text-xs font-semibold text-stone-500 uppercase tracking-wide">Nasıl çalışır?</p>
          <div class="space-y-1.5 text-xs text-stone-500">
            <div class="flex items-center gap-2">
              <span class="flex size-4 items-center justify-center rounded-full bg-orange-100 text-orange-600 font-bold text-[10px]">1</span>
              MetaMask popup'ı açılır, hesabı onaylarsınız
            </div>
            <div class="flex items-center gap-2">
              <span class="flex size-4 items-center justify-center rounded-full bg-orange-100 text-orange-600 font-bold text-[10px]">2</span>
              Bir mesaj imzalamanız istenir (gaz ücreti yok)
            </div>
            <div class="flex items-center gap-2">
              <span class="flex size-4 items-center justify-center rounded-full bg-orange-100 text-orange-600 font-bold text-[10px]">3</span>
              İmzanız doğrulanır, oturumunuz açılır
            </div>
          </div>
        </div>

        <div class="mt-4 text-center text-sm text-stone-500">
          İlk kez mi?
          <RouterLink to="/register" class="font-semibold text-orange-600 hover:text-orange-500 transition">
            Hesap Oluşturun
          </RouterLink>
        </div>
      </div>
    </div>
  </div>
</template>
