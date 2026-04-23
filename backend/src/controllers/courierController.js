import { listCouriers, getCourierLocations } from '../services/courierService.js'

export async function list(req, res) {
  const couriers = await listCouriers()
  res.json(couriers)
}

export async function locations(req, res) {
  const data = await getCourierLocations()
  res.json(data)
}
