import { encodeFunctionData, type Abi, type Address, type Hex } from 'viem'
import { estimateGas, readContract, signTypedData, simulateContract, switchChain, waitForTransactionReceipt, writeContract } from '@wagmi/vue/actions'
import { wagmiConfig, monadTestnetChain } from '@/config/wagmi'
import { contracts } from '@/config/contracts'
import type { QuoteResponse, TypedDataPayload } from '@/api/deliveries'

type ContractCall = {
  address: Address
  abi: Abi
  functionName: string
  args?: readonly unknown[]
  value?: bigint
  account: Address
}

function asBigIntRecord(value: Record<string, unknown>, fields: readonly { name: string; type: string }[]) {
  return Object.fromEntries(Object.entries(value).map(([key, item]) => {
    const field = fields.find(candidate => candidate.name === key)
    return [key, field?.type.startsWith('uint') || field?.type.startsWith('int') ? BigInt(String(item)) : item]
  }))
}

function parseContractError(error: unknown) {
  const candidate = error as { shortMessage?: string; message?: string }
  return new Error(candidate.shortMessage || candidate.message || 'Blockchain işlemi başarısız oldu')
}

export function useDeliveryContract() {
  async function execute(call: ContractCall): Promise<Hex> {
    try {
      await switchChain(wagmiConfig, { chainId: monadTestnetChain.id })
      const request = { chainId: monadTestnetChain.id, ...call } as const
      const simulation = await simulateContract(wagmiConfig, request)
      const data = encodeFunctionData({
        abi: call.abi,
        functionName: call.functionName,
        args: call.args ?? [],
      })
      const estimate = await estimateGas(wagmiConfig, {
        account: call.account,
        chainId: monadTestnetChain.id,
        to: call.address,
        data,
        value: call.value,
      })
      // Monad gas_limit üzerinden ücretlendirir; tahmine yalnız küçük bir güvenlik payı eklenir.
      const gas = estimate + estimate / 10n
      const hash = await writeContract(wagmiConfig, { ...simulation.request, gas })
      const receipt = await waitForTransactionReceipt(wagmiConfig, { hash, confirmations: 1 })
      if (receipt.status !== 'success') throw new Error('İşlem zincirde geri alındı')
      return hash
    } catch (error) {
      throw parseContractError(error)
    }
  }

  async function signBackendTypedData(account: Address, typedData: TypedDataPayload) {
    const fields = typedData.types[typedData.primaryType]
    if (!fields) throw new Error('İmzalanacak veri şeması geçersiz')
    if (Number(typedData.domain.chainId) !== monadTestnetChain.id) throw new Error('İmza chainId değeri Monad Testnet ile eşleşmiyor')
    if (String(typedData.domain.verifyingContract).toLowerCase() !== contracts.deliveryHub.address.toLowerCase()) {
      throw new Error('İmza doğrulama kontratı aktif DeliveryHub ile eşleşmiyor')
    }
    await switchChain(wagmiConfig, { chainId: monadTestnetChain.id })
    return signTypedData(wagmiConfig, {
      account,
      domain: typedData.domain,
      types: typedData.types,
      primaryType: typedData.primaryType,
      message: asBigIntRecord(typedData.message, fields),
    } as Parameters<typeof signTypedData>[1])
  }

  const hubWrite = (account: Address, functionName: string, args: readonly unknown[], value?: bigint) =>
    execute({ ...contracts.deliveryHub, account, functionName, args, value })

  async function createDelivery(account: Address, response: QuoteResponse) {
    const quote = response.quote
    return hubWrite(account, 'createDelivery', [{
      customer: quote.customer,
      riskTier: quote.riskTier,
      declaredValue: BigInt(quote.declaredValue),
      requiredCoverage: BigInt(quote.requiredCoverage),
      issuedAt: BigInt(quote.issuedAt),
      expiresAt: BigInt(quote.expiresAt),
      salt: quote.salt,
    }, response.signature])
  }

  async function bidStakeRequirement(account: Address) {
    const [courier, available, baseDeposit, bidDeposit] = await Promise.all([
      readContract(wagmiConfig, { ...contracts.courierRegistry, functionName: 'courierOf', args: [account] }),
      readContract(wagmiConfig, { ...contracts.courierRegistry, functionName: 'availableStake', args: [account] }),
      readContract(wagmiConfig, { ...contracts.protocolConfig, functionName: 'courierBaseDeposit' }),
      readContract(wagmiConfig, { ...contracts.deliveryHub, functionName: 'bidDeposit' }),
    ])
    const value = courier as readonly [number, boolean, bigint, bigint, bigint, number, number, bigint]
    const stake = value[2]
    const availableStake = available as bigint
    const base = baseDeposit as bigint
    const bid = bidDeposit as bigint
    const forRegistration = base > stake ? base - stake : 0n
    const forBid = bid > availableStake ? bid - availableStake : 0n
    return { requiredDeposit: forRegistration > forBid ? forRegistration : forBid, baseDeposit: base, bidDeposit: bid }
  }

  const acceptanceFields = [
    { name: 'deliveryId', type: 'uint256' }, { name: 'courier', type: 'address' },
    { name: 'action', type: 'bytes32' }, { name: 'nonce', type: 'uint256' }, { name: 'expiresAt', type: 'uint64' },
  ] as const
  const podFields = [
    { name: 'deliveryId', type: 'uint256' }, { name: 'courier', type: 'address' },
    { name: 'proofType', type: 'bytes32' }, { name: 'challengeHash', type: 'bytes32' },
    { name: 'nonce', type: 'uint256' }, { name: 'issuedAt', type: 'uint64' }, { name: 'expiresAt', type: 'uint64' },
  ] as const

  return {
    createDelivery,
    bidStakeRequirement,
    depositStake: (account: Address, value: bigint) =>
      execute({ ...contracts.courierRegistry, account, functionName: 'depositStake', value }),
    placeBid: (account: Address, id: string, ask: bigint, returnAsk: bigint, eta: number, validUntil: bigint) =>
      hubWrite(account, 'placeBid', [BigInt(id), ask, returnAsk, eta, validUntil]),
    selectCourier: (account: Address, id: string, courier: Address, termsVersion: number) =>
      hubWrite(account, 'selectCourier', [BigInt(id), courier, termsVersion]),
    fundCustomer: async (account: Address, id: string) => {
      const value = await readContract(wagmiConfig, { ...contracts.deliveryHub, functionName: 'customerFundingAmount', args: [BigInt(id)] }) as bigint
      return { hash: await hubWrite(account, 'fundAsCustomer', [BigInt(id)], value), value }
    },
    fundCourier: async (account: Address, id: string, requiredCollateral: bigint) => {
      const [available, bidDeposit] = await Promise.all([
        readContract(wagmiConfig, { ...contracts.courierRegistry, functionName: 'availableStake', args: [account] }) as Promise<bigint>,
        readContract(wagmiConfig, { ...contracts.deliveryHub, functionName: 'bidDeposit' }) as Promise<bigint>,
      ])
      // The selected bid's already-reserved deposit is explicitly part of coverage.
      const availableBefore = available + bidDeposit
      const value = requiredCollateral > availableBefore ? requiredCollateral - availableBefore : 0n
      return { hash: await hubWrite(account, 'fundAsCourier', [BigInt(id)], value), value }
    },
    signBackendTypedData,
    confirmPickup: (account: Address, id: string, acceptance: Record<string, string>, signature: Hex) =>
      hubWrite(account, 'confirmPickup', [BigInt(id), asBigIntRecord(acceptance, acceptanceFields), signature]),
    confirmReturn: (account: Address, id: string, acceptance: Record<string, string>, signature: Hex) =>
      hubWrite(account, 'confirmReturn', [BigInt(id), asBigIntRecord(acceptance, acceptanceFields), signature]),
    submitPod: (account: Address, id: string, attestation: Record<string, string>, signature: Hex) =>
      hubWrite(account, 'submitDeliveryProof', [BigInt(id), asBigIntRecord(attestation, podFields), signature]),
    confirmDelivery: (account: Address, id: string) => hubWrite(account, 'confirmDelivery', [BigInt(id)]),
    requestReturn: (account: Address, id: string) => hubWrite(account, 'requestReturn', [BigInt(id)]),
    rateCourier: (account: Address, id: string, rating: number) => hubWrite(account, 'rateCourier', [BigInt(id), rating]),
  }
}
