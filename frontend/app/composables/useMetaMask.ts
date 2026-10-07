import { onMounted, ref, watch } from 'vue'
import { useConnect, useConnection, useConnectors, useSwitchChain, useSignMessage } from '@wagmi/vue'
import { monadTestnetChain } from '@/config/wagmi'

export type MetaMaskError = 'not_installed' | 'user_rejected' | 'request_pending' | 'unknown'

export interface ConnectResult {
  address: string
}

export function useMetaMask() {
  // Keep SSR and the first client render identical; injected providers only
  // exist in the browser and can be inspected after hydration.
  const isInstalled = ref(false)
  const mounted = ref(false)
  const connecting = ref(false)
  const error = ref<MetaMaskError | null>(null)
  const errorMessage = ref('')

  const connectors = useConnectors()
  const connection = useConnection()
  const { mutateAsync: connectAsync } = useConnect()
  const { mutateAsync: switchChainAsync } = useSwitchChain()
  const { mutateAsync: signMessageAsync } = useSignMessage()

  const findMetaMask = () => connectors.value.find(c => c.id === 'io.metamask')
    ?? connectors.value.find(c => c.id === 'metaMask')

  async function detectProvider() {
    if (!mounted.value) return
    isInstalled.value = !!await findMetaMask()?.getProvider().catch(() => undefined)
  }

  onMounted(() => {
    mounted.value = true
    void detectProvider()
  })
  watch(connectors, () => { void detectProvider() })

  function captureError(err: unknown) {
    // Wagmi/viem wrap provider errors; the RPC code can live in a cause.
    let cause: unknown = err
    for (let depth = 0; depth < 8 && cause && typeof cause === 'object'; depth++) {
      const value = cause as { code?: number; cause?: unknown }
      if (value.code === 4001 || value.code === -32002) {
        error.value = value.code === 4001 ? 'user_rejected' : 'request_pending'
        errorMessage.value = value.code === 4001
          ? "MetaMask'ta istek reddedildi. Tekrar deneyin."
          : 'MetaMask’ta bekleyen bir istek var. Eklentiyi açıp isteği tamamlayın.'
        return
      }
      cause = value.cause
    }
    error.value = 'unknown'
    errorMessage.value = (err as { shortMessage?: string })?.shortMessage
      || (err instanceof Error ? err.message.split('\n')[0] ?? '' : '')
      || 'MetaMask bağlantısı kurulamadı. Tekrar deneyin.'
  }

  async function connect(): Promise<ConnectResult | null> {
    if (connecting.value) return null
    if (!isInstalled.value) {
      error.value = 'not_installed'
      return null
    }
    error.value = null
    errorMessage.value = ''
    connecting.value = true
    try {
      const metaMaskConnector = findMetaMask()
      if (!metaMaskConnector) throw new Error('MetaMask bağlayıcısı bulunamadı')

      // The wallet connection survives an expired/rejected SIWE session.
      // Reuse it on retry instead of throwing ConnectorAlreadyConnectedError.
      const current = connection.connector.value
      const alreadyConnected = connection.isConnected.value && current?.uid === metaMaskConnector.uid
      const address = alreadyConnected
        ? (await metaMaskConnector.getAccounts())[0]
        : (await connectAsync({ connector: metaMaskConnector })).accounts[0]
      if (!address) throw new Error('Hesap bulunamadı')

      if (await metaMaskConnector.getChainId() !== monadTestnetChain.id) {
        await switchChainAsync({ chainId: monadTestnetChain.id, connector: metaMaskConnector })
      }

      return { address }
    } catch (err: unknown) {
      captureError(err)
      return null
    } finally {
      connecting.value = false
    }
  }

  async function signMessage(message: string, account: string) {
    try {
      return await signMessageAsync({ account: account as `0x${string}`, message, connector: findMetaMask() })
    } catch (err: unknown) {
      captureError(err)
      throw err
    }
  }

  return { isInstalled, connecting, error, errorMessage, connect, signMessage }
}
