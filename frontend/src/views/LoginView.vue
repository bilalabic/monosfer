<script setup lang="ts">
import { ref } from 'vue'
import { RouterLink, useRouter } from 'vue-router'
import { Mail, Lock, ArrowRight } from 'lucide-vue-next'

const router = useRouter()
const email = ref('')
const password = ref('')
const loading = ref(false)

async function handleLogin() {
  if (!email.value || !password.value) return
  loading.value = true
  // Mock login delay
  await new Promise(r => setTimeout(r, 800))
  loading.value = false
  router.push('/deliveries')
}
</script>

<template>
  <div class="flex min-h-[80vh] items-center justify-center px-5 py-12 sm:px-8">
    <div class="w-full max-w-md">
      <!-- Header -->
      <div class="mb-8 text-center">
        <div class="mx-auto mb-4 flex size-12 items-center justify-center rounded-xl bg-orange-500 shadow-sm">
          <svg class="size-6 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
            <path stroke-linecap="round" stroke-linejoin="round" d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10"/>
          </svg>
        </div>
        <h1 class="text-2xl font-bold text-stone-900">Tekrar Hoş Geldiniz</h1>
        <p class="mt-2 text-sm text-stone-500">Delivera hesabınıza giriş yapın</p>
      </div>

      <!-- Form Card -->
      <div class="card rounded-2xl bg-white p-6 sm:p-8">
        <form @submit.prevent="handleLogin" class="space-y-5">
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
            <div class="mb-1.5 flex items-center justify-between">
              <label class="block text-sm font-medium text-stone-700">Şifre</label>
              <a href="#" class="text-xs font-medium text-orange-600 hover:text-orange-500 transition">Şifremi Unuttum</a>
            </div>
            <div class="relative">
              <Lock class="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-stone-400" />
              <input
                v-model="password"
                type="password"
                placeholder="••••••••"
                class="input pl-10"
                required
              />
            </div>
          </div>

          <button
            type="submit"
            :disabled="loading || !email || !password"
            class="btn-primary w-full justify-center disabled:opacity-50"
          >
            {{ loading ? 'Giriş yapılıyor...' : 'Giriş Yap' }}
            <ArrowRight v-if="!loading" class="size-4" />
          </button>
        </form>

        <div class="mt-6 text-center text-sm text-stone-500">
          Hesabınız yok mu?
          <RouterLink to="/register" class="font-semibold text-orange-600 hover:text-orange-500 transition">
            Hemen Kayıt Olun
          </RouterLink>
        </div>
      </div>
    </div>
  </div>
</template>
