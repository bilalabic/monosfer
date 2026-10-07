import { getChain } from '../../../contracts/exports/index.js'

const chainId = Number(import.meta.env?.VITE_MONOSFER_CHAIN_ID || 10143)
if (![10143, 31337].includes(chainId)) throw new Error('Desteklenmeyen uygulama ağı')
const chain = getChain(chainId)

export const MONAD_TESTNET = {
  chainIdHex: `0x${chain.chainId.toString(16)}`,
  chainId: chain.chainId,
  chainName: chainId === 31337 ? 'Monosfer Yerel Test' : 'Monad Testnet',
  nativeCurrency: { name: 'MON', symbol: 'MON', decimals: 18 },
  rpcUrl: chain.rpcUrl,
  explorer: chain.explorer,
} as const

// EIP-3085 `wallet_addEthereumChain` param shape — derived from MONAD_TESTNET
// so the RPC-facing chain metadata never drifts from the app's own config.
export const MONAD_TESTNET_WALLET_PARAMS = {
  chainId: MONAD_TESTNET.chainIdHex,
  chainName: MONAD_TESTNET.chainName,
  nativeCurrency: MONAD_TESTNET.nativeCurrency,
  rpcUrls: [MONAD_TESTNET.rpcUrl],
  ...(MONAD_TESTNET.explorer ? { blockExplorerUrls: [MONAD_TESTNET.explorer] } : {}),
} as const
