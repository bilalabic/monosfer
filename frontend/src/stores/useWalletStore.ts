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
    balance.value = user.balance ?? 0
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
    const { user, token } = await authApi.login({ walletAddress, email, name: 'Demo Kullanıcı', phone })
    setToken(token)
    applyAuth(user)
  }

  async function fetchBalance() {
    if (!address.value || typeof window === 'undefined' || !window.ethereum) return
    try {
      const hex = await window.ethereum.request({
        method: 'eth_getBalance',
        params: [address.value, 'latest'],
      }) as string
      balance.value = parseFloat((parseInt(hex, 16) / 1e18).toFixed(4))
    } catch {
      // keep current value
    }
  }

  async function connectMetaMask(walletAddress: string) {
    const { user, token } = await authApi.login({ walletAddress })
    setToken(token)
    applyAuth(user)
    await fetchBalance()
  }

  async function registerMetaMask(data: { walletAddress: string; name: string; phone: string; role: 'customer' | 'courier' }) {
    const { user, token } = await authApi.register({ ...data, email: '' })
    setToken(token)
    applyAuth(user)
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

  async function restoreSession() {
    const token = getToken()
    if (!token) return
    try {
      const parts = token.split('.')
      if (parts.length < 2) { clearToken(); return }
      const payload = JSON.parse(atob(parts[1]!))
      if (payload.exp * 1000 < Date.now()) { clearToken(); return }
      if (!payload.walletAddress) { clearToken(); return }
      const { user } = await authApi.login({ walletAddress: payload.walletAddress as string })
      setToken(token)
      applyAuth(user)
      await fetchBalance()
    } catch {
      clearToken()
    }
  }

  return { connected, address, balance, userProfile, displayAddress, connect, connectMetaMask, registerMetaMask, updateProfile, disconnect, restoreSession, fetchBalance }
})
