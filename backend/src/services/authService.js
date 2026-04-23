import jwt from 'jsonwebtoken'
import User from '../models/User.js'

function signToken(user) {
  return jwt.sign(
    { userId: user._id.toString(), walletAddress: user.walletAddress, role: user.role },
    process.env.JWT_SECRET,
    { expiresIn: '7d' },
  )
}

function formatUser(user) {
  return {
    id: user._id.toString(),
    walletAddress: user.walletAddress,
    name: user.name || '',
    email: user.email || '',
    phone: user.phone || '',
    role: user.role || 'customer',
    rating: user.courierProfile?.isRegistered ? 4.5 : 0,
    balance: 0,
  }
}

export async function registerUser({ walletAddress, name, email, phone, role }) {
  const addr = walletAddress.toLowerCase()
  let user = await User.findOne({ walletAddress: addr })
  if (user) {
    const token = signToken(user)
    return { user: formatUser(user), token }
  }
  user = await User.create({ walletAddress: addr, name, email, phone, role: role || 'customer' })
  const token = signToken(user)
  return { user: formatUser(user), token }
}

export async function loginUser({ walletAddress, email, name, phone, role }) {
  const addr = walletAddress.toLowerCase()
  let user = await User.findOne({ walletAddress: addr })
  if (!user) {
    user = await User.create({ walletAddress: addr, email, name, phone, role: role || 'customer' })
  } else if (name && !user.name) {
    user.name = name
    user.email = email || user.email
    user.phone = phone || user.phone
    await user.save()
  }
  const token = signToken(user)
  return { user: formatUser(user), token }
}
