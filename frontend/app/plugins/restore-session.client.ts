import { useWalletStore } from '@/stores/useWalletStore'
import { watchAccount } from '@wagmi/vue/actions'
import { wagmiConfig } from '@/config/wagmi'

export default defineNuxtPlugin(async () => {
  const wallet = useWalletStore()
  window.addEventListener('monosfer:unauthorized', wallet.clearLocalSession)
  await wallet.restoreSession()

  const unwatch = watchAccount(wagmiConfig, {
    onChange(account) {
      wallet.handleWalletAddressChanged(account.address)
    },
  })

  return {
    provide: { stopWalletSessionWatch: unwatch },
  }
})
