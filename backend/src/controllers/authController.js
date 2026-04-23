import { registerUser, loginUser } from '../services/authService.js'

export async function register(req, res) {
  const { walletAddress, name, email, phone, role } = req.body
  if (!walletAddress) return res.status(400).json({ error: { message: 'walletAddress zorunlu' } })
  const result = await registerUser({ walletAddress, name, email, phone, role })
  res.status(201).json(result)
}

export async function login(req, res) {
  const { walletAddress, email, name, phone, role } = req.body
  if (!walletAddress) return res.status(400).json({ error: { message: 'walletAddress zorunlu' } })
  const result = await loginUser({ walletAddress, email, name, phone, role })
  res.json(result)
}
