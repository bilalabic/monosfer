import Delivery from '../models/Delivery.js'
import Bid from '../models/Bid.js'
import User from '../models/User.js'
import CourierStats from '../models/CourierStats.js'

const STATUS_TO_FRONTEND = {
  OpenForBids: 'open',
  Accepted: 'in_progress',
  InTransit: 'in_progress',
  Delivered: 'completed',
  Cancelled: 'disputed',
}

const STATUS_TO_BACKEND = {
  open: 'OpenForBids',
  in_progress: 'Accepted',
  completed: 'Delivered',
  disputed: 'Cancelled',
}

function formatTime(date) {
  if (!date) return undefined
  return new Date(date).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' })
}

async function populateBids(bids, selectedBidId) {
  if (!bids || bids.length === 0) return []
  const wallets = [...new Set(bids.map(b => b.courier))]
  const users = await User.find({ walletAddress: { $in: wallets } }).lean()
  const courierStats = await CourierStats.find({ walletAddress: { $in: wallets } }).lean()
  const userMap = Object.fromEntries(users.map(u => [u.walletAddress, u]))
  const statsMap = Object.fromEntries(courierStats.map(s => [s.walletAddress, s]))

  return bids.map(bid => {
    const user = userMap[bid.courier] || {}
    const stats = statsMap[bid.courier] || {}
    const name = user.name || bid.courier.slice(0, 6) + '...' + bid.courier.slice(-4)
    const initials = name.split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase()
    return {
      id: bid._id.toString(),
      courierId: bid.courier,
      courierName: name,
      courierAvatar: initials,
      courierRating: Number(stats.avgRating || 0),
      courierDeliveries: Number(stats.totalDeliveries || 0),
      tokenAmount: parseFloat(bid.amount) || 0,
      estimatedTime: `${bid.estimatedMinutes} dk`,
      createdAt: bid.createdAt.toISOString(),
    }
  })
}

function buildTimeline(delivery) {
  return delivery.timeline.map(s => ({
    step: s.step,
    label: s.label,
    completed: s.completed,
    time: s.timestamp ? formatTime(s.timestamp) : undefined,
    txHash: s.txHash,
  }))
}

export async function toFrontend(delivery) {
  const bids = await Bid.find({ deliveryId: delivery._id }).lean()
  const populatedBids = await populateBids(bids, delivery.selectedBidId)

  const selectedBid = populatedBids.find(b => b.id === delivery.selectedBidId?.toString())

  return {
    id: delivery._id.toString(),
    title: delivery.title || 'Teslimat',
    pickupAddress: delivery.pickup.address,
    dropoffAddress: delivery.dropoff.address,
    distance: delivery.distanceKm ? `${Number(delivery.distanceKm).toFixed(1)} km` : '—',
    weight: delivery.weight || '—',
    description: delivery.notes || '',
    maxBudget: parseFloat(delivery.maxBudget) || 0,
    escrowAmount: parseFloat(delivery.escrowBalance || delivery.maxBudget) || 0,
    status: STATUS_TO_FRONTEND[delivery.status] || 'open',
    bids: populatedBids,
    selectedBidId: delivery.selectedBidId?.toString(),
    senderId: delivery.customer,
    assignedCourierId: selectedBid?.courierId ?? null,
    createdAt: delivery.createdAt.toISOString(),
    deadline: delivery.deadline?.toISOString() || new Date().toISOString(),
    rating: delivery.rating,
    ratingComment: delivery.ratingComment,
    isRated: Boolean(delivery.isRated),
    timeline: buildTimeline(delivery),
  }
}

export async function listDeliveries({ status, search } = {}) {
  const query = {}
  if (status && status !== 'all') {
    const backendStatus = STATUS_TO_BACKEND[status]
    if (backendStatus === 'in_progress') {
      query.status = { $in: ['Accepted', 'InTransit'] }
    } else if (backendStatus) {
      query.status = backendStatus
    }
  }
  if (search) {
    const q = search.toLowerCase()
    query.$or = [
      { title: { $regex: q, $options: 'i' } },
      { 'pickup.address': { $regex: q, $options: 'i' } },
      { 'dropoff.address': { $regex: q, $options: 'i' } },
    ]
  }
  const deliveries = await Delivery.find(query).sort({ createdAt: -1 }).lean()
  return Promise.all(deliveries.map(toFrontend))
}

export async function getDelivery(id) {
  const delivery = await Delivery.findById(id).lean()
  if (!delivery) return null
  return toFrontend(delivery)
}

export async function createDelivery(data, walletAddress) {
  const deadline = new Date(`${data.date}T${data.deadline}`)
  const delivery = await Delivery.create({
    title: data.title,
    customer: walletAddress.toLowerCase(),
    pickup: {
      address: data.pickupAddress,
      lat: data.pickupLat || 41.0082,
      lng: data.pickupLng || 28.9784,
    },
    dropoff: {
      address: data.dropoffAddress,
      lat: data.dropoffLat || 41.0082,
      lng: data.dropoffLng || 28.9784,
    },
    packageType: data.packageType || 'medium',
    urgency: data.urgency || 'standard',
    weight: data.weight ? `${data.weight} kg` : undefined,
    notes: data.description,
    maxBudget: String(data.maxBudget),
    escrowBalance: '0',
    deadline,
    status: 'OpenForBids',
    timeline: [
      { step: 'created', label: 'Talep Oluşturuldu', completed: true, timestamp: new Date() },
      { step: 'accepted', label: 'Kurye Seçildi', completed: false },
      { step: 'pickup', label: 'Ürün Alındı', completed: false },
      { step: 'transit', label: 'Yolda', completed: false },
      { step: 'delivered', label: 'Teslim Edildi', completed: false },
    ],
  })
  return toFrontend(delivery)
}

export async function addBid(deliveryId, bidData, walletAddress) {
  const delivery = await Delivery.findById(deliveryId)
  if (!delivery) throw Object.assign(new Error('Teslimat bulunamadı'), { statusCode: 404 })
  if (delivery.status !== 'OpenForBids') throw Object.assign(new Error('Teslimat teklife kapalı'), { statusCode: 400 })
  if (delivery.customer === walletAddress.toLowerCase()) throw Object.assign(new Error('Kendi teslimatınıza teklif veremezsiniz'), { statusCode: 403 })
  const existing = await Bid.findOne({ deliveryId, courier: walletAddress.toLowerCase() })
  if (existing) throw Object.assign(new Error('Bu teslimat için zaten teklif verdiniz'), { statusCode: 400 })

  const bid = await Bid.create({
    deliveryId,
    courier: walletAddress.toLowerCase(),
    amount: String(bidData.tokenAmount),
    estimatedMinutes: bidData.estimatedMinutes || 45,
    network: 'monad-testnet',
  })

  const bids = await Bid.find({ deliveryId }).lean()
  const populated = await populateBids(bids, null)
  return populated.find(b => b.id === bid._id.toString())
}

export async function selectBid(deliveryId, bidId, walletAddress) {
  const delivery = await Delivery.findById(deliveryId)
  if (!delivery) throw Object.assign(new Error('Teslimat bulunamadı'), { statusCode: 404 })
  if (delivery.customer !== walletAddress.toLowerCase()) throw Object.assign(new Error('Sadece gönderici teklif seçebilir'), { statusCode: 403 })

  const bid = await Bid.findById(bidId)
  if (!bid) throw Object.assign(new Error('Teklif bulunamadı'), { statusCode: 404 })

  await Bid.updateMany({ deliveryId }, { isSelected: false })
  bid.isSelected = true
  await bid.save()

  delivery.selectedBidId = bid._id
  delivery.status = 'Accepted'
  delivery.acceptedAt = new Date()
  delivery.acceptedAmount = bid.amount
  const acceptedStep = delivery.timeline.find(s => s.step === 'accepted')
  if (acceptedStep) { acceptedStep.completed = true; acceptedStep.timestamp = new Date() }
  await delivery.save()

  return toFrontend(delivery.toObject())
}

export async function lockEscrow(deliveryId, walletAddress, txHash) {
  const delivery = await Delivery.findById(deliveryId)
  if (!delivery) throw Object.assign(new Error('Teslimat bulunamadı'), { statusCode: 404 })
  if (delivery.customer !== walletAddress.toLowerCase()) throw Object.assign(new Error('Sadece gönderici escrow kilitleyebilir'), { statusCode: 403 })
  if (Number(delivery.escrowBalance || 0) > 0) {
    throw Object.assign(new Error("Ödeme zaten escrow'a kilitlenmiş"), { statusCode: 400 })
  }

  delivery.escrowBalance = delivery.maxBudget
  let escrowStep = delivery.timeline.find(s => s.step === 'escrow')
  if (!escrowStep) {
    delivery.timeline.splice(1, 0, {
      step: 'escrow',
      label: "Ödeme Escrow'a Kilitlendi",
      completed: true,
      timestamp: new Date(),
      txHash: txHash || undefined,
    })
  } else {
    escrowStep.completed = true
    escrowStep.timestamp = new Date()
    escrowStep.txHash = txHash || escrowStep.txHash
  }
  await delivery.save()
  return toFrontend(delivery.toObject())
}

export async function confirmPickup(deliveryId, walletAddress, txHash) {
  const delivery = await Delivery.findById(deliveryId)
  if (!delivery) throw Object.assign(new Error('Teslimat bulunamadı'), { statusCode: 404 })
  const assignedBid = delivery.selectedBidId ? await Bid.findById(delivery.selectedBidId) : null
  if (!assignedBid || assignedBid.courier !== walletAddress.toLowerCase()) throw Object.assign(new Error('Sadece atanan kurye teslim alımı onaylayabilir'), { statusCode: 403 })

  delivery.status = 'InTransit'
  delivery.pickedUpAt = new Date()
  for (const s of delivery.timeline) {
    if (s.step === 'pickup' || s.step === 'transit') {
      s.completed = true
      s.timestamp = s.timestamp || new Date()
      s.txHash = txHash || s.txHash
    }
  }
  await delivery.save()
  return toFrontend(delivery.toObject())
}

export async function completeDelivery(deliveryId, walletAddress, txHash) {
  const delivery = await Delivery.findById(deliveryId)
  if (!delivery) throw Object.assign(new Error('Teslimat bulunamadı'), { statusCode: 404 })
  const assignedBid = delivery.selectedBidId ? await Bid.findById(delivery.selectedBidId) : null
  if (!assignedBid || assignedBid.courier !== walletAddress.toLowerCase()) throw Object.assign(new Error('Sadece atanan kurye teslimatı tamamlayabilir'), { statusCode: 403 })

  delivery.status = 'Delivered'
  delivery.deliveredAt = new Date()
  delivery.escrowBalance = '0'
  for (const s of delivery.timeline) {
    if (!s.completed) {
      s.completed = true
      s.timestamp = new Date()
      if (s.step === 'delivered') s.txHash = txHash || s.txHash
    }
  }
  await delivery.save()
  return toFrontend(delivery.toObject())
}

export async function rateDelivery(deliveryId, walletAddress, data) {
  const rating = Number(data?.rating)
  if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
    throw Object.assign(new Error('Puan 1 ile 5 arasında olmalı'), { statusCode: 400 })
  }

  const delivery = await Delivery.findById(deliveryId)
  if (!delivery) throw Object.assign(new Error('Teslimat bulunamadı'), { statusCode: 404 })
  if (delivery.customer !== walletAddress.toLowerCase()) {
    throw Object.assign(new Error('Sadece ödemeyi yapan gönderici puan verebilir'), { statusCode: 403 })
  }
  if (delivery.status !== 'Delivered') {
    throw Object.assign(new Error('Sadece tamamlanan teslimatlar puanlanabilir'), { statusCode: 400 })
  }
  if (delivery.isRated) {
    throw Object.assign(new Error('Bu teslimat zaten puanlandı'), { statusCode: 400 })
  }

  const assignedBid = delivery.selectedBidId ? await Bid.findById(delivery.selectedBidId) : null
  if (!assignedBid) throw Object.assign(new Error('Puanlanacak kurye bulunamadı'), { statusCode: 400 })

  delivery.rating = rating
  delivery.ratingComment = typeof data?.comment === 'string' ? data.comment.trim().slice(0, 500) : ''
  delivery.isRated = true
  delivery.ratedAt = new Date()

  let stats = await CourierStats.findOne({ walletAddress: assignedBid.courier })
  if (!stats) {
    stats = await CourierStats.create({ walletAddress: assignedBid.courier })
  }

  stats.totalRatings = Number(stats.totalRatings || 0) + 1
  stats.totalRatingSum = Number(stats.totalRatingSum || 0) + rating
  stats.avgRating = Math.round((stats.totalRatingSum / stats.totalRatings) * 10) / 10
  stats.leaderboardScore = Math.round(
    (Number(stats.totalDeliveries || 0) * 10) +
    (Number(stats.onTimeRate || 0) * 0.5) +
    (stats.avgRating * 20),
  )

  await stats.save?.()
  await delivery.save()
  return toFrontend(delivery.toObject())
}
