import User from '../models/User.js'
import CourierStats from '../models/CourierStats.js'
import Delivery from '../models/Delivery.js'
import Bid from '../models/Bid.js'

function sameWeek(a, b) {
  const first = new Date(a)
  first.setHours(0, 0, 0, 0)
  first.setDate(first.getDate() - first.getDay())
  const second = new Date(b)
  second.setHours(0, 0, 0, 0)
  second.setDate(second.getDate() - second.getDay())
  return first.getTime() === second.getTime()
}

function sameMonth(a, b) {
  const first = new Date(a)
  const second = new Date(b)
  return first.getFullYear() === second.getFullYear() && first.getMonth() === second.getMonth()
}

async function buildDerivedStats() {
  const deliveries = await Delivery.find({ status: 'Delivered', selectedBidId: { $ne: null } })
    .select('selectedBidId deliveredAt deadline')
    .lean()
  if (deliveries.length === 0) return {}

  const bidIds = deliveries.map(delivery => delivery.selectedBidId)
  const bids = await Bid.find({ _id: { $in: bidIds } })
    .select('_id courier amount')
    .lean()
  const bidMap = Object.fromEntries(bids.map(bid => [bid._id.toString(), bid]))
  const now = new Date()

  return deliveries.reduce((acc, delivery) => {
    const bid = bidMap[delivery.selectedBidId?.toString()]
    if (!bid) return acc

    const deliveredAt = delivery.deliveredAt || now
    const amount = Number(bid.amount || 0)
    const stats = acc[bid.courier] || {
      totalDeliveries: 0,
      onTimeCount: 0,
      lateCount: 0,
      weeklyDeliveries: 0,
      monthlyDeliveries: 0,
      weeklyEarnings: 0,
      monthlyEarnings: 0,
      totalEarnings: 0,
      successRate: 100,
      onTimeRate: 0,
      leaderboardScore: 0,
    }

    stats.totalDeliveries += 1
    stats.totalEarnings += amount
    if (!delivery.deadline || new Date(deliveredAt) <= new Date(delivery.deadline)) {
      stats.onTimeCount += 1
    } else {
      stats.lateCount += 1
    }
    if (sameWeek(deliveredAt, now)) {
      stats.weeklyDeliveries += 1
      stats.weeklyEarnings += amount
    }
    if (sameMonth(deliveredAt, now)) {
      stats.monthlyDeliveries += 1
      stats.monthlyEarnings += amount
    }
    stats.onTimeRate = Math.round((stats.onTimeCount / stats.totalDeliveries) * 100)
    stats.leaderboardScore = Math.round((stats.totalDeliveries * 10) + (stats.onTimeRate * 0.5))
    acc[bid.courier] = stats
    return acc
  }, {})
}

export async function listCouriers() {
  const users = await User.find({})
    .select('walletAddress name role courierProfile createdAt')
    .lean()

  if (users.length === 0) return []

  const addrs = users.map(u => u.walletAddress)
  const statsArr = await CourierStats.find({ walletAddress: { $in: addrs } }).lean()
  const statsMap = Object.fromEntries(statsArr.map(s => [s.walletAddress, s]))
  const derivedStatsMap = await buildDerivedStats()

  return users.map(u => {
    const persisted = statsMap[u.walletAddress] || {}
    const derived = derivedStatsMap[u.walletAddress] || {}
    const hasPersistedDeliveries = Number(persisted.totalDeliveries || 0) > 0
    const s = hasPersistedDeliveries ? persisted : { ...derived, avgRating: persisted.avgRating || 0 }
    const initials = (u.name || '')
      .split(' ')
      .filter(Boolean)
      .map(w => w[0])
      .join('')
      .toUpperCase()
      .slice(0, 2) || u.walletAddress.slice(2, 4).toUpperCase()

    return {
      id: u._id.toString(),
      walletAddress: u.walletAddress,
      name: u.name || `Kurye ${u.walletAddress.slice(0, 6)}`,
      avatar: initials,
      rating: Math.round((s.avgRating || 0) * 10) / 10,
      totalDeliveries: s.totalDeliveries || 0,
      successRate: Math.round(s.successRate || 0),
      onTimeRate: Math.round(s.onTimeRate || 0),
      weeklyDeliveries: s.weeklyDeliveries || 0,
      weeklyEarnings: parseFloat(s.weeklyEarnings || '0'),
      monthlyEarnings: parseFloat(s.monthlyEarnings || '0'),
      joinedDate: u.createdAt ? new Date(u.createdAt).toISOString().split('T')[0] : '',
      specialties: u.courierProfile?.specialties || [],
      leaderboardScore: s.leaderboardScore || 0,
    }
  })
}
