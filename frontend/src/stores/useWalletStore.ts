import { defineStore } from 'pinia'
import { ref } from 'vue'
import { authApi } from '@/api/auth'
import { setToken, clearToken, getToken } from '@/api/client'

export const useWalletStore = defineStore('wallet', () => {
  const connected = ref(false)
  const address = ref('')
  const balance = ref(0)

  const userProfile = ref({
    name: '',
    email: '',
    phone: '',
    role: 'customer' as 'customer' | 'courier',
    rating: 0,
  })

  const displayAddress = () =>
    address.value ? `${address.value.slice(0, 6)}...${address.value.slice(-4)}` : ''

  function applyAuth(user: { walletAddress: string; name: string; email: string; phone: string; role: 'customer' | 'courier'; rating: number; balance: number }) {
    connected.value = true
    address.value = user.walletAddress
    balance.value = user.balance ?? 248.5
    userProfile.value = {
      name: user.name || 'Kullanıcı',
      email: user.email || '',
      phone: user.phone || '',
      role: user.role || 'customer',
      rating: user.rating ?? 0,
    }
  }

  async function connect(email = 'test@example.com', phone = '') {
    const walletAddress = '0x71C7656EC7ab88b098defB751B7401B5f6d8976F'
    try {
      const { user, token } = await authApi.login({ walletAddress, email, name: 'Yusuf Arslan', phone })
      setToken(token)
      applyAuth({ ...user, balance: 248.5 })
    } catch {
      // API unavailable — use mock
      connected.value = true
      address.value = walletAddress
      balance.value = 248.5
      userProfile.value = { name: 'Yusuf Arslan', email, phone: phone || '+90 555 123 4567', role: 'customer', rating: 4.8 }
    }
  }

  async function register(data: { name: string; email: string; phone: string; role: 'customer' | 'courier' }) {
    const walletAddress = `0x${Math.random().toString(16).slice(2).padEnd(40, '0')}`
    try {
      const { user, token } = await authApi.register({ walletAddress, ...data })
      setToken(token)
      applyAuth({ ...user, balance: 50 })
    } catch {
      // API unavailable — use mock
      connected.value = true
      address.value = walletAddress
      balance.value = 50
      userProfile.value = { ...data, rating: 0 }
    }
  }

  function updateProfile(data: Partial<typeof userProfile.value>) {
    userProfile.value = { ...userProfile.value, ...data }
  }

  function disconnect() {
    connected.value = false
    address.value = ''
    balance.value = 0
    userProfile.value = { name: '', email: '', phone: '', role: 'customer', rating: 0 }
    clearToken()
  }

  // Restore session from stored token on app load
  async function restoreSession() {
    const token = getToken()
    if (!token) return
    try {
      // Decode payload without verifying (verification happens on backend)
      const parts = token.split('.')
      if (parts.length < 2) { clearToken(); return }
      const payload = JSON.parse(atob(parts[1]!))
      if (payload.exp * 1000 < Date.now()) { clearToken(); return }
      if (!payload.walletAddress) { clearToken(); return }
      const { user } = await authApi.login({ walletAddress: payload.walletAddress as string })
      setToken(token) // keep same token
      applyAuth({ ...user, balance: 248.5 })
    } catch {
      clearToken()
    }
  }

  async function connectMetaMask(walletAddress: string) {
    try {
      const { user, token } = await authApi.login({ walletAddress })
      setToken(token)
      applyAuth({ ...user, balance: user.balance ?? 248.5 })
    } catch {
      connected.value = true
      address.value = walletAddress
      balance.value = 0
      userProfile.value = { name: '', email: '', phone: '', role: 'customer', rating: 0 }
    }
  }

  async function registerMetaMask(data: { walletAddress: string; name: string; phone: string; role: 'customer' | 'courier' }) {
    try {
      const { user, token } = await authApi.register({ ...data, email: '' })
      setToken(token)
      applyAuth({ ...user, balance: user.balance ?? 50 })
    } catch {
      connected.value = true
      address.value = data.walletAddress
      balance.value = 50
      userProfile.value = { name: data.name, email: '', phone: data.phone, role: data.role, rating: 0 }
    }
  }

  return { connected, address, balance, userProfile, displayAddress, connect, register, connectMetaMask, registerMetaMask, updateProfile, disconnect, restoreSession }
})
