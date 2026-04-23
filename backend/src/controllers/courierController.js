import { listCouriers } from '../services/courierService.js'

export async function list(req, res) {
  const couriers = await listCouriers()
  res.json(couriers)
}
