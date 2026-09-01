import { ref, computed } from 'vue'
import { MONAD_TESTNET, MONAD_TESTNET_WALLET_PARAMS } from '@/config/chain'

declare global {
  interface Window {
    ethereum?: {
      isMetaMask?: boolean
      request: (args: { method: string; params?: unknown[] }) => Promise<unknown>
      on: (event: string, handler: (...args: unknown[]) => void) => void
      removeListener: (event: string, handler: (...args: unknown[]) => void) => void
    }
  }
}

export type MetaMaskError = 'not_installed' | 'user_rejected' | 'unknown'

export interface ConnectResult {
  address: string
  signature: string
  message: string
}

export function useMetaMask() {
  const isInstalled = computed(() => typeof window !== 'undefined' && !!window.ethereum?.isMetaMask)
  const connecting = ref(false)
  const error = ref<MetaMaskError | null>(null)

  async function requestAccount(): Promise<string> {
    const accounts = await window.ethereum!.request({ method: 'eth_requestAccounts' }) as string[]
    if (!accounts[0]) throw new Error('Hesap bulunamadı')
    return accounts[0]
  }

  async function signMessage(address: string, message: string): Promise<string> {
    return window.ethereum!.request({
      method: 'personal_sign',
      params: [message, address],
    }) as Promise<string>
  }

  async function switchToMonad(): Promise<void> {
    try {
      await window.ethereum!.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: MONAD_TESTNET.chainIdHex }],
      })
    } catch (err: unknown) {
      if ((err as { code?: number }).code === 4902) {
        await window.ethereum!.request({
          method: 'wallet_addEthereumChain',
          params: [MONAD_TESTNET_WALLET_PARAMS],
        })
      }
    }
  }

  async function connect(): Promise<ConnectResult | null> {
    if (!isInstalled.value) {
      error.value = 'not_installed'
      return null
    }
    error.value = null
    connecting.value = true
    try {
      const address = await requestAccount()
      await switchToMonad()
      const message = `Delivera'ya giriş yapıyorum: ${Date.now()}`
      const signature = await signMessage(address, message)
      return { address, signature, message }
    } catch (err: unknown) {
      const code = (err as { code?: number }).code
      error.value = code === 4001 ? 'user_rejected' : 'unknown'
      return null
    } finally {
      connecting.value = false
    }
  }

  return { isInstalled, connecting, error, connect }
}
