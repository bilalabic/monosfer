import { defineStore } from 'pinia'
import { ref } from 'vue'
import { authApi, type AuthUser, type UserRole } from '@/api/auth'
import { setToken, clearToken, getToken } from '@/api/client'

type UserProfile = Pick<AuthUser, 'name' | 'email' | 'phone' | 'role' | 'rating'>

export const useWalletStore = defineStore('wallet', () => {
  const connected = ref(false)
  const address = ref('')
  const balance = ref(0)

  const userProfile = ref({
    name: '',
    email: '',
    phone: '',
    role: 'both' as UserRole,
    rating: 0,
  })

  const displayAddress = () =>
    address.value ? `${address.value.slice(0, 6)}...${address.value.slice(-4)}` : ''

  function applyAuth(user: AuthUser) {
    connected.value = true
    address.value = user.walletAddress
    balance.value = user.balance ?? 0
    userProfile.value = {
      name: user.name || 'Kullanıcı',
      email: user.email || '',
      phone: user.phone || '',
      role: user.role || 'both',
      rating: user.rating ?? 0,
    }
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

  async function registerMetaMask(data: { walletAddress: string; name: string; phone: string; role: UserRole }) {
    const { user, token } = await authApi.register({ ...data, email: '' })
    setToken(token)
    applyAuth(user)
  }

  async function updateProfile(data: Partial<UserProfile>) {
    const { user } = await authApi.updateMe(data)
    applyAuth(user)
  }

  function disconnect() {
    connected.value = false
    address.value = ''
    balance.value = 0
    userProfile.value = { name: '', email: '', phone: '', role: 'both', rating: 0 }
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
      const { user } = await authApi.me()
      applyAuth(user)
      await fetchBalance()
    } catch {
      clearToken()
    }
  }

  return { connected, address, balance, userProfile, displayAddress, connectMetaMask, registerMetaMask, updateProfile, disconnect, restoreSession, fetchBalance }
})
