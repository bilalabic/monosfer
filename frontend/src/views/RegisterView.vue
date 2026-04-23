<script setup lang="ts">
import { ref } from 'vue'
import { RouterLink, useRouter } from 'vue-router'
import { PhUser as User, PhEnvelopeSimple as Mail, PhLockKey as Lock, PhArrowRight as ArrowRight, PhPackage as Package, PhTruck as Truck, PhPhone as Phone } from '@phosphor-icons/vue'
import { useWalletStore } from '@/stores/useWalletStore'

const router = useRouter()
const wallet = useWalletStore()
const accountType = ref<'customer' | 'courier'>('customer')
const name = ref('')
const email = ref('')
const phone = ref('')
const password = ref('')
const loading = ref(false)

async function handleRegister() {
  if (!name.value || !email.value || !phone.value || !password.value) return
  loading.value = true
  await new Promise(r => setTimeout(r, 1000))
  loading.value = false
  wallet.register({ name: name.value, email: email.value, phone: phone.value, role: accountType.value })
  router.push('/dashboard')
}
</script>

<template>
  <div class="flex min-h-[80vh] items-center justify-center px-5 py-12 sm:px-8">
    <div class="w-full max-w-md">
      <!-- Header -->
      <div class="mb-8 text-center">
        <h1 class="text-2xl font-bold text-stone-900">Hesap Oluştur</h1>
        <p class="mt-2 text-sm text-stone-500">Delivera ağına katılın ve hemen başlayın</p>
      </div>

      <!-- Form Card -->
      <div class="card rounded-2xl bg-white p-6 sm:p-8">
        <!-- Account Type Selector -->
        <div class="mb-6 grid grid-cols-2 gap-3 rounded-xl border border-stone-100 bg-stone-50 p-1.5">
          <button
            type="button"
            :class="[
              'flex flex-col items-center gap-1.5 rounded-lg py-2.5 text-xs font-medium transition-all',
              accountType === 'customer'
                ? 'bg-white text-stone-900 shadow-sm ring-1 ring-stone-200'
                : 'text-stone-500 hover:bg-stone-100'
            ]"
            @click="accountType = 'customer'"
          >
            <Package class="size-4" :class="accountType === 'customer' ? 'text-orange-500' : ''" weight="duotone" />
            Müşteri
          </button>
          <button
            type="button"
            :class="[
              'flex flex-col items-center gap-1.5 rounded-lg py-2.5 text-xs font-medium transition-all',
              accountType === 'courier'
                ? 'bg-white text-stone-900 shadow-sm ring-1 ring-stone-200'
                : 'text-stone-500 hover:bg-stone-100'
            ]"
            @click="accountType = 'courier'"
          >
            <Truck class="size-4" :class="accountType === 'courier' ? 'text-orange-500' : ''" weight="duotone" />
            Kurye
          </button>
        </div>

        <form @submit.prevent="handleRegister" v-auto-animate class="space-y-4">
          <div>
            <label class="mb-1.5 block text-sm font-medium text-stone-700">Ad Soyad</label>
            <div class="relative">
              <User class="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-stone-400" weight="bold" />
              <input
                v-model="name"
                type="text"
                placeholder="Adınız Soyadınız"
                class="input pl-10"
                required
              />
            </div>
          </div>

          <div>
            <label class="mb-1.5 block text-sm font-medium text-stone-700">Telefon Numarası</label>
            <div class="relative">
              <Phone class="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-stone-400" weight="bold" />
              <input
                v-model="phone"
                type="tel"
                placeholder="Örn: 0555 123 4567"
                class="input pl-10"
              />
            </div>
          </div>

          <div>
            <label class="mb-1.5 block text-sm font-medium text-stone-700">E-posta Adresi</label>
            <div class="relative">
              <Mail class="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-stone-400" weight="bold" />
              <input
                v-model="email"
                type="email"
                placeholder="ornek@email.com"
                class="input pl-10"
                required
              />
            </div>
          </div>

          <div>
            <label class="mb-1.5 block text-sm font-medium text-stone-700">Şifre</label>
            <div class="relative">
              <Lock class="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-stone-400" weight="bold" />
              <input
                v-model="password"
                type="password"
                placeholder="En az 8 karakter"
                class="input pl-10"
                required
                minlength="8"
              />
            </div>
            <p v-if="accountType === 'courier'" class="mt-2 text-xs text-stone-400">
              * Kurye profilinizi giriş yaptıktan sonra tamamlayabilirsiniz.
            </p>
          </div>

          <button
            type="submit"
            :disabled="loading || !name || !email || !password"
            class="mt-2 btn-primary w-full justify-center disabled:opacity-50"
          >
            {{ loading ? 'Hesap oluşturuluyor...' : 'Kayıt Ol' }}
            <ArrowRight v-if="!loading" class="size-4" weight="bold" />
          </button>
        </form>

        <div class="mt-6 text-center text-sm text-stone-500">
          Zaten hesabınız var mı?
          <RouterLink to="/login" class="font-semibold text-orange-600 hover:text-orange-500 transition">
            Giriş Yapın
          </RouterLink>
        </div>
      </div>
    </div>
  </div>
</template>
