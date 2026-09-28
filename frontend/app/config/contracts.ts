import type { Abi } from 'viem'
import { getAddress, ABIS } from '../../../contracts/exports/index.js'

export const contracts = {
  deliveryHub: { address: getAddress(10143, 'DeliveryHub'), abi: ABIS.DeliveryHub as Abi },
  courierRegistry: { address: getAddress(10143, 'CourierRegistry'), abi: ABIS.CourierRegistry as Abi },
  protocolConfig: { address: getAddress(10143, 'ProtocolConfig'), abi: ABIS.ProtocolConfig as Abi },
} as const
