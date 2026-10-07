import type { Abi } from 'viem'
import { getAddress, ABIS } from '../../../contracts/exports/index.js'
import { MONAD_TESTNET } from './chain'

export const contracts = {
  deliveryHub: { address: getAddress(MONAD_TESTNET.chainId, 'DeliveryHub'), abi: ABIS.DeliveryHub as Abi },
  courierRegistry: { address: getAddress(MONAD_TESTNET.chainId, 'CourierRegistry'), abi: ABIS.CourierRegistry as Abi },
  protocolConfig: { address: getAddress(MONAD_TESTNET.chainId, 'ProtocolConfig'), abi: ABIS.ProtocolConfig as Abi },
} as const
