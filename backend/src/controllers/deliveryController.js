import * as deliveryService from '../services/deliveryService.js'
import User from '../models/User.js'

export async function list(req, res) {
  const { status, search } = req.query
  const deliveries = await deliveryService.listDeliveries({ status, search })
  res.json(deliveries)
}

export async function getOne(req, res) {
  const delivery = await deliveryService.getDelivery(req.params.id)
  if (!delivery) return res.status(404).json({ error: { message: 'Teslimat bulunamadı', statusCode: 404 } })
  res.json(delivery)
}

export async function create(req, res) {
  const delivery = await deliveryService.createDelivery(req.body, req.user.walletAddress)
  res.status(201).json(delivery)
}

export async function addBid(req, res) {
  const bid = await deliveryService.addBid(req.params.id, req.body, req.user.walletAddress)
  res.status(201).json(bid)
}

export async function selectBid(req, res) {
  const { bidId } = req.body
  if (!bidId) return res.status(400).json({ error: { message: 'bidId zorunlu' } })
  const delivery = await deliveryService.selectBid(req.params.id, bidId, req.user.walletAddress)
  res.json(delivery)
}

export async function lockEscrow(req, res) {
  const delivery = await deliveryService.lockEscrow(req.params.id, req.user.walletAddress, req.body?.txHash)
  res.json(delivery)
}

export async function confirmPickup(req, res) {
  const delivery = await deliveryService.confirmPickup(req.params.id, req.user.walletAddress, req.body?.txHash)
  res.json(delivery)
}

export async function complete(req, res) {
  const delivery = await deliveryService.completeDelivery(req.params.id, req.user.walletAddress, req.body?.txHash)
  res.json(delivery)
}

export async function completeWithRecipientCode(req, res) {
  const delivery = await deliveryService.completeDeliveryWithRecipientCode(req.params.id, req.body?.deliveryCode, req.body?.txHash)
  res.json(delivery)
}

export async function rate(req, res) {
  const delivery = await deliveryService.rateDelivery(req.params.id, req.user.walletAddress, req.body)
  res.json(delivery)
}

// Teslimat sahibi için: kuryenin canlı konumunu döndür
export async function courierLocation(req, res) {
  const Delivery = (await import('../models/Delivery.js')).default
  const delivery = await Delivery.findById(req.params.id).lean()

  if (!delivery) return res.status(404).json({ error: { message: 'Teslimat bulunamadı' } })

  // Sadece teslimat sahibi görebilir
  if (delivery.customer !== req.user.walletAddress) {
    return res.status(403).json({ error: { message: 'Erişim izni yok' } })
  }

  // Kurye kargoyu almadan önce konum gösterilmez
  const allowedStatuses = ['InTransit', 'Delivered']
  if (!allowedStatuses.includes(delivery.status)) {
    return res.status(400).json({ error: { message: 'Kurye henüz kargoyu teslim almadı' }, status: delivery.status })
  }

  if (!delivery.acceptedCourier) {
    return res.status(404).json({ error: { message: 'Atanmış kurye bulunamadı' } })
  }

  const courier = await User.findOne({ walletAddress: delivery.acceptedCourier })
    .select('name walletAddress courierProfile')
    .lean()

  if (!courier) return res.status(404).json({ error: { message: 'Kurye bulunamadı' } })

  const cp = courier.courierProfile || {}

  // Demo: gerçek konum yoksa pickup ile dropoff arasında ilerleyen bir konum simüle et
  let lat = cp.location?.lat
  let lng = cp.location?.lng

  if (!lat || !lng) {
    // pickup ve dropoff arasında %40-80 ilerlemiş bir nokta simüle et
    const progress = 0.4 + Math.random() * 0.4
    lat = delivery.pickup.lat + (delivery.dropoff.lat - delivery.pickup.lat) * progress
    lng = delivery.pickup.lng + (delivery.dropoff.lng - delivery.pickup.lng) * progress
    // küçük rastgele sapma (gerçekçilik için)
    lat += (Math.random() - 0.5) * 0.003
    lng += (Math.random() - 0.5) * 0.003
  }

  res.json({
    courierId: courier._id.toString(),
    courierName: courier.name || `Kurye ${courier.walletAddress.slice(0, 6)}`,
    courierWallet: courier.walletAddress,
    isOnline: cp.isOnline ?? true,
    vehicleType: cp.vehicleType || 'motorcycle',
    lat,
    lng,
    locationUpdatedAt: cp.location?.updatedAt || null,
    deliveryStatus: delivery.status,
    pickup: { lat: delivery.pickup.lat, lng: delivery.pickup.lng, address: delivery.pickup.address },
    dropoff: { lat: delivery.dropoff.lat, lng: delivery.dropoff.lng, address: delivery.dropoff.address },
  })
}
