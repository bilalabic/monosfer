export const MONAD_TESTNET = {
  chainIdHex: '0x279f',
  chainId: 10143,
  rpcUrl: 'https://testnet-rpc.monad.xyz',
  explorer: 'https://testnet.monadexplorer.com',
  contracts: {
    token: '0xda4f523b0d55fb6ce61515c4d003a70ca55948cd',
    escrow: '0x91023fb41c5a308c12ab68c037207f832426d067',
    leaderboard: '0x5a887f8c32e3299309212686acaad9b108aa883c',
    distributor: '0x6e7ed62ab956f79e16d870d0b3796dffca6903f2',
    badge: '0x8b44b40e24c16174eb0df623212f341e230ae83c',
  },
} as const
