import { defineStore } from 'pinia'
import { ref } from 'vue'
import { formatEther } from 'viem'
import { getBalance } from '@wagmi/vue/actions'
import { authApi, type AuthUser, type UserRole } from '@/api/auth'
import { setToken, clearToken, getToken } from '@/api/client'
import { wagmiConfig, monadTestnetChain } from '@/config/wagmi'

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
    if (!address.value) return
    try {
      const result = await getBalance(wagmiConfig, {
        address: address.value as `0x${string}`,
        chainId: monadTestnetChain.id,
      })
      balance.value = parseFloat(parseFloat(formatEther(result.value)).toFixed(4))
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
