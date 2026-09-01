import { createConfig, http, cookieStorage, createStorage } from '@wagmi/vue'
import { metaMask } from '@wagmi/vue/connectors'
import { defineChain } from 'viem'
import { MONAD_TESTNET } from './chain'

export const monadTestnetChain = defineChain({
  id: MONAD_TESTNET.chainId,
  name: MONAD_TESTNET.chainName,
  nativeCurrency: MONAD_TESTNET.nativeCurrency,
  rpcUrls: {
    default: { http: [MONAD_TESTNET.rpcUrl] },
  },
  blockExplorers: {
    default: { name: 'Monad Explorer', url: MONAD_TESTNET.explorer },
  },
})

export const wagmiConfig = createConfig({
  chains: [monadTestnetChain],
  connectors: [metaMask()],
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
