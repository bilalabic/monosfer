import { computed, ref } from 'vue'
import { defineStore } from 'pinia'
import { formatEther, parseEther, type Address, type Hex } from 'viem'
import {
  deliveriesApi,
  type ChainBid,
  type ChainDelivery,
  type ChainDeliveryState,
  type CreateQuoteInput,
  type IndexerStatus,
} from '@/api/deliveries'
import { useDeliveryContract } from '@/composables/useDeliveryContract'
import { useWalletStore } from '@/stores/useWalletStore'
import { developmentDataset, type DevelopmentCourier, type DevelopmentDelivery } from '@/api/development'

export type DeliveryStatus =
  | 'open'
  | 'in_progress'
  | 'completed'
  | 'returned'
  | 'resolved'
  | 'cancelled'
  | 'expired'
  | 'disputed'
export type RecipientType = 'person' | 'business' | 'office' | 'other'

export interface Bid {
  id: string
  courierId: string
  courierName: string
  courierAvatar: string
  courierRating: number
  courierDeliveries: number
  tokenAmount: number
  returnAmount: number
  estimatedTime: string
  createdAt: string
  validUntil: string
  termsVersion: number
  active: boolean
}

export interface TimelineStep {
  step: string
  label: string
  completed: boolean
  time?: string
  role?: 'sender' | 'courier' | 'recipient' | 'system'
}

export interface Delivery {
  id: string
  title: string
  pickupAddress: string
  dropoffAddress: string
  recipientType?: RecipientType
  recipientName?: string
  distance: string
  weight: string
  description: string
  maxBudget: number
  escrowAmount: number
  status: DeliveryStatus
  chainState: ChainDeliveryState
  bids: Bid[]
  selectedBidId?: string
  senderId?: string
  assignedCourierId?: string | null
  createdAt: string
  deadline: string
  rating?: number
  isRated?: boolean
  timeline: TimelineStep[]
  customerFunded: boolean
  courierFunded: boolean
  requiredCollateralWei: string
  indexing: IndexerStatus
  creationTxHash: string
}

export interface CreateDeliveryInput {
  title: string
  pickupAddress: string
  pickupLat: number
  pickupLng: number
  dropoffAddress: string
  dropoffLat: number
  dropoffLng: number
  recipientType?: RecipientType
  recipientName?: string
  businessName?: string
  contactPerson?: string
  orderRef?: string
  department?: string
  recipientPhone?: string
  recipientWallet?: string
  recipientNote?: string
  deliveryCode?: string
  weight?: string
  description?: string
  maxBudget: number
  date: string
  deadline: string
}

interface SignedAcceptancePackage {
  version: 1
  kind: 'pickup' | 'return'
  deliveryId: string
  acceptance: Record<string, string>
  signature: Hex
  expiresAt: string
}

const zeroAddress = '0x0000000000000000000000000000000000000000'
const stateOrder: ChainDeliveryState[] = [
  'Bidding', 'AwaitingFunding', 'ReadyForPickup', 'InTransit', 'DeliveredPending',
  'ReturnRequired', 'Disputed', 'Completed', 'Returned', 'Resolved', 'Cancelled', 'Expired',
]

const wait = (ms: number) => new Promise(resolve => setTimeout(resolve, ms))
const toMon = (value: string) => Number(formatEther(BigInt(value || '0')))
const unixDate = (seconds: string) => new Date(Number(seconds || '0') * 1000).toISOString()
const shortAddress = (address: string) => `${address.slice(0, 6)}...${address.slice(-4)}`

function appStatus(state: ChainDeliveryState): DeliveryStatus {
  if (state === 'Bidding') return 'open'
  if (state === 'Disputed') return 'disputed'
  if (state === 'Completed') return 'completed'
  if (state === 'Returned') return 'returned'
  if (state === 'Resolved') return 'resolved'
  if (state === 'Cancelled') return 'cancelled'
  if (state === 'Expired') return 'expired'
  return 'in_progress'
}

function timeline(state: ChainDeliveryState): TimelineStep[] {
  const current = stateOrder.indexOf(state)
  return [
    { step: 'created', label: 'Zincirde yayınlandı', completed: current >= 0, role: 'sender' },
    { step: 'selected', label: 'Kurye seçildi', completed: current >= 1, role: 'sender' },
    { step: 'funded', label: 'İki taraf fonladı', completed: current >= 2, role: 'system' },
    { step: 'pickup', label: 'Paket teslim alındı', completed: current >= 3, role: 'courier' },
    { step: 'proof', label: 'Teslim kanıtı gönderildi', completed: current >= 4, role: 'courier' },
    { step: 'completed', label: 'Teslimat sonuçlandı', completed: ['Completed', 'Returned', 'Resolved'].includes(state), role: 'recipient' },
  ]
}

function mapBid(bid: ChainBid): Bid {
  return {
    id: bid.courier.toLowerCase(),
    courierId: bid.courier.toLowerCase(),
    courierName: shortAddress(bid.courier),
    courierAvatar: '',
    courierRating: 0,
    courierDeliveries: 0,
    tokenAmount: toMon(bid.courierAsk),
    returnAmount: toMon(bid.returnAsk),
    estimatedTime: `${bid.etaMinutes} dk`,
    createdAt: unixDate(bid.validUntil),
    validUntil: unixDate(bid.validUntil),
    termsVersion: Number(bid.termsVersion),
    active: bid.active,
  }
}

function mapDelivery(delivery: ChainDelivery, bids: ChainBid[], indexing: IndexerStatus, fixture?: DevelopmentDelivery, couriers: DevelopmentCourier[] = []): Delivery {
  const courier = delivery.courier.toLowerCase() === zeroAddress ? null : delivery.courier.toLowerCase()
  const ask = toMon(delivery.courierAsk)
  const funded = delivery.customerFunded ? ask + toMon(delivery.protocolFee) + toMon(delivery.returnReserve) : 0
  return {
    id: delivery.id,
    title: fixture?.title || `Teslimat #${delivery.id}`,
    pickupAddress: fixture?.pickupArea || 'Adres yalnız doğrulanmış katılımcılara açıktır',
    dropoffAddress: fixture?.dropoffArea || 'Adres yalnız doğrulanmış katılımcılara açıktır',
    distance: fixture?.distance || 'Özel rota',
    weight: fixture?.weight || `Risk seviyesi R${delivery.riskTier}`,
    description: fixture?.description || 'Finalized Monad teslimat kaydı',
    maxBudget: fixture?.budget || ask || toMon(delivery.requiredCollateral),
    escrowAmount: funded,
    status: appStatus(delivery.state),
    chainState: delivery.state,
    bids: bids.map(bid => ({ ...mapBid(bid), courierName: couriers.find(item => item.walletAddress === bid.courier.toLowerCase())?.name || shortAddress(bid.courier) })),
    selectedBidId: courier ?? undefined,
    senderId: delivery.customer.toLowerCase(),
    assignedCourierId: courier,
    createdAt: fixture?.createdAt || unixDate(delivery.stateDeadline),
    deadline: unixDate(delivery.stateDeadline),
    timeline: timeline(delivery.state),
    customerFunded: delivery.customerFunded,
    courierFunded: delivery.courierFunded,
    requiredCollateralWei: delivery.requiredCollateral,
    indexing,
    creationTxHash: delivery.creationTxHash,
  }
}

export const useDeliveryStore = defineStore('delivery', () => {
  const deliveries = ref<Delivery[]>([])
  const loading = ref(false)
  const error = ref('')
  const indexer = ref<IndexerStatus | null>(null)
  const selectedFilter = ref<'all' | DeliveryStatus>('all')
  const contract = useDeliveryContract()

  const filteredDeliveries = computed(() => {
    if (selectedFilter.value === 'all') return deliveries.value
    return deliveries.value.filter(delivery => delivery.status === selectedFilter.value)
  })

  const getDelivery = (id: string) => deliveries.value.find(delivery => delivery.id === id)

  function replaceDelivery(updated: Delivery) {
    const existing = deliveries.value.findIndex(delivery => delivery.id === updated.id)
    if (existing === -1) deliveries.value.unshift(updated)
    else deliveries.value[existing] = updated
  }

  function connectedAccount() {
    const address = useWalletStore().address
    if (!address) throw new Error('Önce cüzdan oturumu açmalısınız')
    return address as Address
  }

  async function fetchDelivery(id: string) {
    const [projection, bidPage, dataset] = await Promise.all([deliveriesApi.get(id), deliveriesApi.bids(id), developmentDataset()])
    indexer.value = projection.indexing
    if (!projection.data) return null
    const mapped = mapDelivery(projection.data, bidPage.data, projection.indexing, dataset.deliveries.find(item => item.id === id), dataset.couriers)
    replaceDelivery(mapped)
    return mapped
  }

  async function loadDeliveries() {
    const nuxtApp = useNuxtApp()
    loading.value = true
    error.value = ''
    try {
      const [page, dataset] = await Promise.all([deliveriesApi.list({ limit: 100 }), developmentDataset()])
      indexer.value = page.indexing
      const bidPages = await nuxtApp.runWithContext(() => Promise.all(page.data.map(delivery => deliveriesApi.bids(delivery.id))))
      deliveries.value = page.data.map((delivery, index) => mapDelivery(delivery, bidPages[index]?.data ?? [], page.indexing, dataset.deliveries.find(item => item.id === delivery.id), dataset.couriers))
      if (page.indexing.status !== 'ready') {
        error.value = `Zincir verisi ${page.indexing.status}; işlemler için finalized projection bekleniyor.`
      }
    } catch (cause) {
      error.value = cause instanceof Error ? cause.message : 'Teslimatlar yüklenemedi'
    } finally {
      loading.value = false
    }
  }

  async function waitForDelivery(id: string, ready: (delivery: Delivery) => boolean) {
    for (let attempt = 0; attempt < 24; attempt += 1) {
      await wait(attempt === 0 ? 800 : 1000)
      const current = await fetchDelivery(id).catch(() => null)
      if (current && ready(current) && current.indexing.status === 'ready') return current
    }
    error.value = 'İşlem zincirde onaylandı; finalized indexer projection hâlâ güncelleniyor.'
    return getDelivery(id) ?? null
  }

  async function createDelivery(form: CreateDeliveryInput) {
    const account = connectedAccount()
    const weight = Number(form.weight || 0)
    const packageType: CreateQuoteInput['metadata']['packageType'] = weight <= 1 ? 'small' : weight <= 10 ? 'medium' : 'large'
    const requestedAt = new Date(`${form.date}T${form.deadline}`).getTime()
    const remainingHours = (requestedAt - Date.now()) / 3_600_000
    const urgency: CreateQuoteInput['metadata']['urgency'] = remainingHours <= 2 ? 'instant' : remainingHours <= 8 ? 'express' : 'standard'
    const dropoff = Object.fromEntries(Object.entries({
      address: form.dropoffAddress,
      lat: form.dropoffLat,
      lng: form.dropoffLng,
      recipientName: form.recipientName,
      businessName: form.businessName,
      contactPerson: form.contactPerson,
      department: form.department,
      recipientPhone: form.recipientPhone,
      recipientNote: form.recipientNote,
      orderNumber: form.orderRef,
      deliveryCode: form.deliveryCode,
      recipientWallet: form.recipientWallet,
    }).filter(([, value]) => value !== '' && value !== undefined)) as CreateQuoteInput['privatePayload']['dropoff']
    const quote = await deliveriesApi.createQuote({
      declaredValue: parseEther(String(form.maxBudget)).toString(),
      metadata: { packageType, urgency },
      privatePayload: {
        pickup: { address: form.pickupAddress, lat: form.pickupLat, lng: form.pickupLng },
        dropoff,
        notes: [form.title, form.weight ? `${form.weight} kg` : '', form.description].filter(Boolean).join(' · '),
      },
    })
    await contract.createDelivery(account, quote)
    for (let attempt = 0; attempt < 30; attempt += 1) {
      await wait(1000)
      const status = await deliveriesApi.quoteStatus(quote.quoteDigest).catch(() => null)
      if (status?.status === 'linked' && status.deliveryId) {
        const created = await fetchDelivery(status.deliveryId)
        if (created?.indexing.status === 'ready') return created
      }
    }
    throw new Error('Teslimat zincirde oluşturuldu; finalized indexer bağlantısı henüz hazır değil. Listeyi biraz sonra yenileyin.')
  }

  async function bidStakeRequirement() {
    return contract.bidStakeRequirement(connectedAccount())
  }

  async function addBid(deliveryId: string, input: { tokenAmount: number; returnAmount: number; estimatedMinutes: number; requiredStake?: bigint }) {
    const account = connectedAccount()
    if (input.requiredStake && input.requiredStake > 0n) await contract.depositStake(account, input.requiredStake)
    await contract.placeBid(
      account,
      deliveryId,
      parseEther(String(input.tokenAmount)),
      parseEther(String(input.returnAmount)),
      input.estimatedMinutes,
      BigInt(Math.floor(Date.now() / 1000) + 3600),
    )
    return waitForDelivery(deliveryId, delivery => delivery.bids.some(bid => bid.courierId === account.toLowerCase() && bid.active))
  }

  async function selectBid(deliveryId: string, bidId: string) {
    const delivery = getDelivery(deliveryId)
    const bid = delivery?.bids.find(candidate => candidate.id === bidId)
    if (!delivery || !bid) throw new Error('Teklif finalized projection içinde bulunamadı')
    await contract.selectCourier(connectedAccount(), deliveryId, bid.courierId as Address, bid.termsVersion)
    return waitForDelivery(deliveryId, current => current.chainState === 'AwaitingFunding' && current.assignedCourierId === bid.courierId)
  }

  async function lockEscrow(deliveryId: string) {
    const result = await contract.fundCustomer(connectedAccount(), deliveryId)
    await waitForDelivery(deliveryId, delivery => delivery.customerFunded)
    return result
  }

  async function fundCourier(deliveryId: string) {
    const delivery = getDelivery(deliveryId)
    if (!delivery) throw new Error('Teslimat bulunamadı')
    const result = await contract.fundCourier(connectedAccount(), deliveryId, BigInt(delivery.requiredCollateralWei))
    await waitForDelivery(deliveryId, current => current.courierFunded)
    return result
  }

  async function issueAcceptance(deliveryId: string, kind: 'pickup' | 'return') {
    const account = connectedAccount()
    const response = kind === 'pickup'
      ? await deliveriesApi.pickupAcceptance(deliveryId)
      : await deliveriesApi.returnAcceptance(deliveryId)
    const signature = await contract.signBackendTypedData(account, response.typedData)
    const payload: SignedAcceptancePackage = {
      version: 1,
      kind,
      deliveryId,
      acceptance: response.acceptance,
      signature,
      expiresAt: response.expiresAt,
    }
    return JSON.stringify(payload)
  }

  function parseAcceptance(deliveryId: string, payload: string, kind: 'pickup' | 'return') {
    let parsed: SignedAcceptancePackage
    try { parsed = JSON.parse(payload) as SignedAcceptancePackage } catch { throw new Error('İmzalı kabul paketi geçerli JSON değil') }
    if (parsed.version !== 1 || parsed.kind !== kind || parsed.deliveryId !== deliveryId || !parsed.signature?.startsWith('0x')) {
      throw new Error('İmzalı kabul paketi bu teslimat ve aksiyonla eşleşmiyor')
    }
    if (Date.parse(parsed.expiresAt) <= Date.now()) throw new Error('İmzalı kabul paketinin süresi dolmuş')
    const assignedCourier = getDelivery(deliveryId)?.assignedCourierId
    if (!assignedCourier || String(parsed.acceptance.courier).toLowerCase() !== assignedCourier || assignedCourier !== connectedAccount().toLowerCase()) {
      throw new Error('İmzalı kabul paketi atanmış kurye cüzdanıyla eşleşmiyor')
    }
    return parsed
  }

  async function confirmPickup(deliveryId: string, payload: string) {
    const parsed = parseAcceptance(deliveryId, payload, 'pickup')
    await contract.confirmPickup(connectedAccount(), deliveryId, parsed.acceptance, parsed.signature)
    return waitForDelivery(deliveryId, delivery => delivery.chainState === 'InTransit')
  }

  async function requestReturn(deliveryId: string) {
    await contract.requestReturn(connectedAccount(), deliveryId)
    return waitForDelivery(deliveryId, delivery => delivery.chainState === 'ReturnRequired')
  }

  async function confirmReturn(deliveryId: string, payload: string) {
    const parsed = parseAcceptance(deliveryId, payload, 'return')
    await contract.confirmReturn(connectedAccount(), deliveryId, parsed.acceptance, parsed.signature)
    return waitForDelivery(deliveryId, delivery => delivery.chainState === 'Returned')
  }

  async function completeDeliveryWithRecipientCode(deliveryId: string, deliveryCode: string) {
    const proof = await deliveriesApi.podAttestation(deliveryId, deliveryCode)
    await contract.submitPod(connectedAccount(), deliveryId, proof.attestation, proof.signature)
    return waitForDelivery(deliveryId, delivery => delivery.chainState === 'DeliveredPending')
  }

  async function completeDelivery(deliveryId: string) {
    await contract.confirmDelivery(connectedAccount(), deliveryId)
    return waitForDelivery(deliveryId, delivery => delivery.chainState === 'Completed')
  }

  async function rateDelivery(deliveryId: string, rating: number, _comment?: string) {
    const delivery = getDelivery(deliveryId)
    await contract.rateCourier(connectedAccount(), deliveryId, rating)
    if (delivery) {
      delivery.rating = rating
      delivery.isRated = true
    }
    return delivery
  }

  return {
    deliveries, loading, error, indexer, filteredDeliveries, selectedFilter,
    getDelivery, loadDeliveries, fetchDelivery, createDelivery, bidStakeRequirement,
    addBid, selectBid, lockEscrow, fundCourier, issueAcceptance, confirmPickup,
    requestReturn, confirmReturn, completeDelivery, completeDeliveryWithRecipientCode, rateDelivery,
  }
})
