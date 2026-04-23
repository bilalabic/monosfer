<script setup lang="ts">
import { ref } from 'vue'
import { RouterLink, useRouter } from 'vue-router'
import { User, Mail, Lock, ArrowRight, Package, Truck } from 'lucide-vue-next'

const router = useRouter()
const accountType = ref<'customer' | 'courier'>('customer')
const name = ref('')
const email = ref('')
const password = ref('')
const loading = ref(false)

async function handleRegister() {
  if (!name.value || !email.value || !password.value) return
  loading.value = true
  // Mock register delay
  await new Promise(r => setTimeout(r, 1000))
  loading.value = false
  router.push('/deliveries')
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
            <Package class="size-4" :class="accountType === 'customer' ? 'text-orange-500' : ''" />
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
            <Truck class="size-4" :class="accountType === 'courier' ? 'text-orange-500' : ''" />
            Kurye
          </button>
        </div>

        <form @submit.prevent="handleRegister" class="space-y-4">
          <div>
            <label class="mb-1.5 block text-sm font-medium text-stone-700">Ad Soyad</label>
            <div class="relative">
              <User class="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-stone-400" />
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
            <label class="mb-1.5 block text-sm font-medium text-stone-700">E-posta Adresi</label>
            <div class="relative">
              <Mail class="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-stone-400" />
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
              <Lock class="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-stone-400" />
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
            <ArrowRight v-if="!loading" class="size-4" />
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
