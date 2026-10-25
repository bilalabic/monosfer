export const MONAD_TESTNET = {
  chainIdHex: '0x279f',
  chainId: 10143,
  rpcUrl: 'https://testnet-rpc.monad.xyz',
  explorer: 'https://testnet.monadexplorer.com',
  contracts: {
    token: import.meta.env.VITE_TOKEN_ADDRESS || '',
    escrow: import.meta.env.VITE_ESCROW_ADDRESS || '',
    leaderboard: import.meta.env.VITE_LEADERBOARD_ADDRESS || '',
    distributor: import.meta.env.VITE_DISTRIBUTOR_ADDRESS || '',
    badge: import.meta.env.VITE_BADGE_ADDRESS || '',
  },
} as const
