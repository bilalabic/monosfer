import jwt from 'jsonwebtoken'
import User from '../models/User.js'
import CourierStats from '../models/CourierStats.js'

function signToken(user) {
  return jwt.sign(
    { userId: user._id.toString(), walletAddress: user.walletAddress, role: user.role },
    process.env.JWT_SECRET,
    { expiresIn: '7d' },
  )
}

async function formatUser(user) {
  let rating = 0
  if (user.courierProfile?.isRegistered || user.role === 'courier' || user.role === 'both') {
    const stats = await CourierStats.findOne({ walletAddress: user.walletAddress }).lean()
    rating = Number(stats?.avgRating || 0)
  }

  return {
    id: user._id.toString(),
    walletAddress: user.walletAddress,
    name: user.name || '',
    email: user.email || '',
    phone: user.phone || '',
    role: user.role || 'both',
    rating,
    balance: 0,
  }
}

export async function registerUser({ walletAddress, name, email, phone, role }) {
  const addr = walletAddress.toLowerCase()
  let user = await User.findOne({ walletAddress: addr })
  if (user) {
    const token = signToken(user)
    return { user: await formatUser(user), token }
  }
  user = await User.create({ walletAddress: addr, name, email, phone, role: role || 'both' })
  const token = signToken(user)
  return { user: await formatUser(user), token }
}

export async function loginUser({ walletAddress, email, name, phone, role }) {
  const addr = walletAddress.toLowerCase()
  let user = await User.findOne({ walletAddress: addr })
  if (!user) {
    user = await User.create({ walletAddress: addr, email, name, phone, role: role || 'both' })
  } else if (name && !user.name) {
    user.name = name
    user.email = email || user.email
    user.phone = phone || user.phone
    user.role = role || user.role || 'both'
    await user.save()
  } else if (user.role === 'customer') {
    user.role = 'both'
    await user.save()
  }
  const token = signToken(user)
  return { user: await formatUser(user), token }
}

export async function getCurrentUser({ userId, walletAddress }) {
  const query = userId ? { _id: userId } : { walletAddress: walletAddress?.toLowerCase() }
  const user = await User.findOne(query)
  if (!user) throw Object.assign(new Error('Kullanıcı bulunamadı'), { statusCode: 404 })
  return { user: await formatUser(user) }
}

export async function updateCurrentUser({ userId, walletAddress }, data) {
  const query = userId ? { _id: userId } : { walletAddress: walletAddress?.toLowerCase() }
  const user = await User.findOne(query)
  if (!user) throw Object.assign(new Error('Kullanıcı bulunamadı'), { statusCode: 404 })

  if (typeof data.name === 'string') user.name = data.name.trim()
  if (typeof data.phone === 'string') user.phone = data.phone.trim()
  if (typeof data.email === 'string') user.email = data.email.trim().toLowerCase()
  if (['customer', 'courier', 'both'].includes(data.role)) user.role = data.role

  await user.save()
  return { user: await formatUser(user) }
}
