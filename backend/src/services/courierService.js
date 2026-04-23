import User from '../models/User.js'
import CourierStats from '../models/CourierStats.js'

export async function listCouriers() {
  const users = await User.find({})
    .select('walletAddress name role courierProfile createdAt')
    .lean()

  if (users.length === 0) return []

  const addrs = users.map(u => u.walletAddress)
  const statsArr = await CourierStats.find({ walletAddress: { $in: addrs } }).lean()
  const statsMap = Object.fromEntries(statsArr.map(s => [s.walletAddress, s]))

  return users.map(u => {
    const s = statsMap[u.walletAddress] || {}
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
