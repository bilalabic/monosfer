import { createConfig, http, cookieStorage, createStorage } from '@wagmi/vue'
import { injected } from '@wagmi/vue/connectors'
import { defineChain } from 'viem'
import { MONAD_TESTNET } from './chain'

export const monadTestnetChain = defineChain({
  id: MONAD_TESTNET.chainId,
  name: MONAD_TESTNET.chainName,
  nativeCurrency: MONAD_TESTNET.nativeCurrency,
  rpcUrls: {
    default: { http: [MONAD_TESTNET.rpcUrl] },
  },
  blockExplorers: MONAD_TESTNET.explorer ? {
    default: { name: 'Monad Explorer', url: MONAD_TESTNET.explorer },
  } : undefined,
})

export const wagmiConfig = createConfig({
  chains: [monadTestnetChain],
  // The UI connects to the installed extension, so use its EIP-1193 provider
  // directly rather than the optional MetaMask Connect SDK.
  connectors: [injected({ target: 'metaMask' })],
  transports: {
    [monadTestnetChain.id]: http(),
  },
  ssr: true,
  storage: createStorage({ storage: cookieStorage }),
})

declare module '@wagmi/vue' {
  interface Register {
    config: typeof wagmiConfig
  }
}
