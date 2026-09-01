import { WagmiPlugin, cookieToInitialState } from '@wagmi/vue'
import { VueQueryPlugin } from '@tanstack/vue-query'
import { wagmiConfig } from '@/config/wagmi'

export default defineNuxtPlugin((nuxtApp) => {
  const initialState = import.meta.server
    ? cookieToInitialState(wagmiConfig, useRequestHeaders(['cookie']).cookie)
    : undefined

  nuxtApp.vueApp.use(WagmiPlugin, { config: wagmiConfig, initialState })
  nuxtApp.vueApp.use(VueQueryPlugin, {})
})
