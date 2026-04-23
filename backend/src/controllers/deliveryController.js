import * as deliveryService from '../services/deliveryService.js'

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
  const delivery = await deliveryService.selectBid(req.params.id, bidId)
  res.json(delivery)
}

export async function lockEscrow(req, res) {
  const delivery = await deliveryService.lockEscrow(req.params.id)
  res.json(delivery)
}

export async function confirmPickup(req, res) {
  const delivery = await deliveryService.confirmPickup(req.params.id)
  res.json(delivery)
}

export async function complete(req, res) {
  const delivery = await deliveryService.completeDelivery(req.params.id)
  res.json(delivery)
}
