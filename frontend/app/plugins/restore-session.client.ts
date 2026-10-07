import { useWalletStore } from '@/stores/useWalletStore'
import { watchAccount } from '@wagmi/vue/actions'
import { wagmiConfig } from '@/config/wagmi'

export default defineNuxtPlugin(async (nuxtApp) => {
  const wallet = useWalletStore()
  const router = useRouter()
  window.addEventListener('monosfer:unauthorized', wallet.clearLocalSession)
  if (nuxtApp.payload.serverRendered) {
    // Public pages hydrate the guest markup produced by SSR. Applying the
    // private cookie session before hydration changes navbar/cards mid-hydrate.
    nuxtApp.hook('app:mounted', async () => {
      await wallet.restoreSession()
      const route = router.currentRoute.value
      if (route.meta.requiresAuth && !wallet.connected) await router.replace('/login')
      else if (['/login', '/register'].includes(route.path) && wallet.connected) await router.replace('/dashboard')
    })
  } else {
    // Protected routes skip SSR and still need auth before their route guard.
    await wallet.restoreSession()
  }

  const unwatch = watchAccount(wagmiConfig, {
    onChange(account) {
      wallet.handleWalletAddressChanged(account.address)
    },
  })

  return {
    provide: { stopWalletSessionWatch: unwatch },
  }
})
