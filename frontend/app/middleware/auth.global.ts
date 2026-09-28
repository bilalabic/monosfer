import { useWalletStore } from '@/stores/useWalletStore'

export default defineNuxtRouteMiddleware((to) => {
  // Wallet/session state is restored client-side from the HttpOnly cookie
  // in app/plugins/restore-session.client.ts — never redirect during SSR,
  // or every navigation would bounce to /login on the very first paint.
  if (import.meta.server) return

  const wallet = useWalletStore()

  if (to.meta.requiresAuth && !wallet.connected) {
    return navigateTo('/login')
  }

  if ((to.path === '/login' || to.path === '/register') && wallet.connected) {
    return navigateTo('/dashboard')
  }
})
