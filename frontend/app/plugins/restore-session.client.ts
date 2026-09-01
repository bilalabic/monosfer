import { useWalletStore } from '@/stores/useWalletStore'

export default defineNuxtPlugin(() => {
  useWalletStore().restoreSession()
})
