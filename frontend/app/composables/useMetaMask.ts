import { computed, ref } from 'vue'
import { useConnect, useConnectors, useSwitchChain, useSignMessage } from '@wagmi/vue'
import { monadTestnetChain } from '@/config/wagmi'

declare global {
  interface Window {
    ethereum?: {
      isMetaMask?: boolean
    }
  }
}

export type MetaMaskError = 'not_installed' | 'user_rejected' | 'unknown'

export interface ConnectResult {
  address: string
}

export function useMetaMask() {
  const isInstalled = computed(() => typeof window !== 'undefined' && !!window.ethereum?.isMetaMask)
  const connecting = ref(false)
  const error = ref<MetaMaskError | null>(null)

  const connectors = useConnectors()
  const { mutateAsync: connectAsync } = useConnect()
  const { mutateAsync: switchChainAsync } = useSwitchChain()
  const { mutateAsync: signMessageAsync } = useSignMessage()

  async function connect(): Promise<ConnectResult | null> {
    if (!isInstalled.value) {
      error.value = 'not_installed'
      return null
    }
    error.value = null
    connecting.value = true
    try {
      const metaMaskConnector = connectors.value.find(c => c.id === 'metaMask') ?? connectors.value[0]
      if (!metaMaskConnector) throw new Error('MetaMask bağlayıcısı bulunamadı')

      const { accounts } = await connectAsync({ connector: metaMaskConnector })
      const address = accounts[0]
      if (!address) throw new Error('Hesap bulunamadı')

      await switchChainAsync({ chainId: monadTestnetChain.id })

      return { address }
    } catch (err: unknown) {
      const code = (err as { code?: number })?.code
      error.value = code === 4001 ? 'user_rejected' : 'unknown'
      return null
    } finally {
      connecting.value = false
    }
  }

  async function signMessage(message: string, account: string) {
    try {
      return await signMessageAsync({ account: account as `0x${string}`, message })
    } catch (err: unknown) {
      const code = (err as { code?: number })?.code
      error.value = code === 4001 ? 'user_rejected' : 'unknown'
      throw err
    }
  }

  return { isInstalled, connecting, error, connect, signMessage }
}
