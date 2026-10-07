<script setup lang="ts">
import { ref, computed } from 'vue'
import { PhArrowRight, PhUser, PhPhone, PhCheckCircle, PhWarning } from '@phosphor-icons/vue'
import { useWalletStore } from '@/stores/useWalletStore'
import { useMetaMask } from '@/composables/useMetaMask'

const router = useRouter()
const wallet = useWalletStore()
const mm = useMetaMask()

type Step = 'wallet' | 'profile'
const step = ref<Step>('wallet')
const connectedAddress = ref('')

const name = ref('')
const phone = ref('')
const loading = ref(false)
const submitError = ref('')

const canSubmit = computed(() => !!name.value.trim() && !!phone.value.trim())

async function handleMetaMask() {
  const result = await mm.connect()
  if (!result) return
  connectedAddress.value = result.address
  step.value = 'profile'
}

async function handleSubmit() {
  if (!canSubmit.value) return
  loading.value = true
  submitError.value = ''
  try {
    await wallet.registerMetaMask({
      walletAddress: connectedAddress.value,
      name: name.value,
      phone: phone.value,
      role: 'customer',
      signer: mm.signMessage,
    })
    router.push('/dashboard')
  } catch (e) {
    submitError.value = e instanceof Error ? e.message : 'Hesap oluşturulamadı, tekrar deneyin.'
  } finally {
    loading.value = false
  }
}

function shortAddr(addr: string) {
  return addr ? `${addr.slice(0, 6)}...${addr.slice(-4)}` : ''
}
</script>

<template>
  <div class="auth-page flex min-h-[80vh] items-center justify-center px-5 py-12 sm:px-8">
    <div class="w-full max-w-md">

      <!-- Header -->
      <page-header compact centered eyebrow="Teslimatın geleceğine katıl" title="Hesap Oluştur" description="Cüzdanını bağla. Gönderici veya kurye olarak ilk yolculuğuna başla." />

      <!-- Step indicator -->
      <div class="mb-6 flex items-center gap-3">
        <div class="flex flex-1 items-center gap-2">
          <div class="flex size-6 items-center justify-center rounded-full text-xs font-bold"
               :class="step === 'wallet' ? 'bg-orange-500 text-white' : 'bg-green-500 text-white'">
            <PhCheckCircle v-if="step === 'profile'" class="size-4" weight="fill" />
            <span v-else>1</span>
          </div>
          <span class="text-xs font-medium" :class="step === 'wallet' ? 'text-stone-900' : 'text-stone-400'">Cüzdan Bağla</span>
        </div>
        <div class="h-px w-8 bg-stone-200" />
        <div class="flex flex-1 items-center gap-2">
          <div class="flex size-6 items-center justify-center rounded-full text-xs font-bold"
               :class="step === 'profile' ? 'bg-orange-500 text-white' : 'bg-stone-200 text-stone-400'">2</div>
          <span class="text-xs font-medium" :class="step === 'profile' ? 'text-stone-900' : 'text-stone-400'">Profil Bilgileri</span>
        </div>
      </div>

      <div class="card rounded-2xl bg-white p-6 shadow-sm" v-auto-animate>

        <!-- STEP 1: Wallet connect -->
        <template v-if="step === 'wallet'">
          <!-- MetaMask not installed -->
          <div v-if="!mm.isInstalled.value" class="mb-5 rounded-xl border border-amber-200 bg-amber-50 p-4">
            <div class="flex items-start gap-3">
              <PhWarning class="mt-0.5 size-4 shrink-0 text-amber-600" weight="fill" />
              <div>
                <p class="text-sm font-semibold text-amber-800">MetaMask bulunamadı</p>
                <a href="https://metamask.io/download/" target="_blank" rel="noopener noreferrer"
                   class="mt-1 inline-flex items-center gap-1 text-xs font-semibold text-amber-700 underline underline-offset-2">
                  MetaMask İndir →
                </a>
              </div>
            </div>
          </div>

          <div v-if="mm.error.value === 'user_rejected'" class="mb-4 rounded-xl border border-red-200 bg-red-50 p-3 text-xs text-red-700">
            MetaMask'ta isteği reddettiniz. Tekrar deneyin.
          </div>
          <div v-else-if="mm.error.value" class="mb-4 rounded-xl border border-red-200 bg-red-50 p-3 text-xs text-red-700">
            {{ mm.errorMessage.value || 'Bağlantı hatası oluştu. Tekrar deneyin.' }}
          </div>

          <button
            class="group flex w-full items-center justify-center gap-3 rounded-xl px-5 py-4 font-semibold text-white transition-all disabled:opacity-60"
            :class="mm.isInstalled.value ? 'bg-[#F6851B] hover:bg-[#E2761B] shadow-md hover:shadow-lg' : 'bg-stone-300 cursor-not-allowed'"
            :disabled="mm.connecting.value || !mm.isInstalled.value"
            @click="handleMetaMask"
          >
            <svg class="size-6 shrink-0" viewBox="0 0 318.6 318.6" xmlns="http://www.w3.org/2000/svg">
              <polygon fill="#E2761B" stroke="#E2761B" stroke-linecap="round" stroke-linejoin="round" points="274.1,35.5 174.6,109.4 193,65.8"/>
              <polygon fill="#E4761B" stroke="#E4761B" stroke-linecap="round" stroke-linejoin="round" points="44.4,35.5 143.1,110.1 125.6,65.8"/>
              <polygon fill="#D7C1B3" stroke="#D7C1B3" stroke-linecap="round" stroke-linejoin="round" points="238.3,206.8 211.8,247.4 268.5,263 284.8,207.7"/>
              <polygon fill="#D7C1B3" stroke="#D7C1B3" stroke-linecap="round" stroke-linejoin="round" points="33.9,207.7 50.1,263 106.8,247.4 80.3,206.8"/>
              <polygon fill="#D7C1B3" stroke="#D7C1B3" stroke-linecap="round" stroke-linejoin="round" points="103.6,138.2 87.8,162.1 144.1,164.6 142.1,104.1"/>
              <polygon fill="#D7C1B3" stroke="#D7C1B3" stroke-linecap="round" stroke-linejoin="round" points="214.9,138.2 175.9,103.4 174.6,164.6 230.8,162.1"/>
              <polygon fill="#233447" stroke="#233447" stroke-linecap="round" stroke-linejoin="round" points="106.8,247.4 140.6,230.9 111.4,208.1"/>
              <polygon fill="#233447" stroke="#233447" stroke-linecap="round" stroke-linejoin="round" points="177.9,230.9 211.8,247.4 207.1,208.1"/>
              <polygon fill="#F6851B" stroke="#F6851B" stroke-linecap="round" stroke-linejoin="round" points="106.8,247.4 111.6,206.8 80.3,207.7"/>
              <polygon fill="#F6851B" stroke="#F6851B" stroke-linecap="round" stroke-linejoin="round" points="207,206.8 211.8,247.4 238.3,207.7"/>
              <polygon fill="#F6851B" stroke="#F6851B" stroke-linecap="round" stroke-linejoin="round" points="230.8,162.1 174.6,164.6 179.8,193.5 188,176.1 208.1,185.2"/>
              <polygon fill="#F6851B" stroke="#F6851B" stroke-linecap="round" stroke-linejoin="round" points="110.6,185.2 130.6,176.1 138.8,193.5 144.1,164.6 87.8,162.1"/>
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
          </button>

          <p class="mt-4 text-center text-xs text-stone-400">
            Cüzdan adresiniz kimliğiniz olur — şifre gerekmez.
          </p>

          <div class="mt-5 text-center text-sm text-stone-500">
            Hesabınız var mı?
            <NuxtLink to="/login" class="font-semibold text-orange-600 hover:text-orange-500 transition">Giriş Yapın</NuxtLink>
          </div>
        </template>

        <!-- STEP 2: Profile info -->
        <template v-else>
          <!-- Connected address -->
          <div class="mb-5 flex items-center gap-3 rounded-xl border border-green-200 bg-green-50 p-3">
            <PhCheckCircle class="size-5 shrink-0 text-green-500" weight="fill" />
            <div>
              <p class="text-xs font-semibold text-green-700">Cüzdan Bağlandı</p>
              <p class="font-mono text-xs text-stone-600">{{ shortAddr(connectedAddress) }}</p>
            </div>
          </div>

          <div class="space-y-4">
            <div>
              <label class="mb-1.5 block text-sm font-medium text-stone-700">Ad Soyad</label>
              <div class="relative">
                <PhUser class="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-stone-400" weight="bold" />
                <input v-model="name" type="text" placeholder="Adınız Soyadınız" class="input pl-10" required />
              </div>
            </div>

            <div>
              <label class="mb-1.5 block text-sm font-medium text-stone-700">Telefon</label>
              <div class="relative">
                <PhPhone class="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-stone-400" weight="bold" />
                <input v-model="phone" type="tel" placeholder="0555 123 4567" class="input pl-10" required />
              </div>
            </div>

            <button
              :disabled="!canSubmit || loading"
              class="btn-primary w-full justify-center disabled:opacity-50"
              @click="handleSubmit"
            >
              {{ loading ? 'Hesap oluşturuluyor...' : 'Hesabı Tamamla' }}
              <PhArrowRight v-if="!loading" class="size-4" weight="bold" />
            </button>
            <p v-if="submitError" class="mt-3 rounded-xl border border-red-200 bg-red-50 p-3 text-center text-xs text-red-700">
              {{ submitError }}
            </p>
          </div>
        </template>
      </div>
    </div>
  </div>
</template>
