import { getChain } from '../../../contracts/exports/index.js'

const chain = getChain(10143)

export const MONAD_TESTNET = {
  chainIdHex: `0x${chain.chainId.toString(16)}`,
  chainId: chain.chainId,
  chainName: 'Monad Testnet',
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
  blockExplorerUrls: [MONAD_TESTNET.explorer],
} as const
