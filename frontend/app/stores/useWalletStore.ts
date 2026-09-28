import { defineStore } from 'pinia'
import { ref } from 'vue'
import { formatEther } from 'viem'
import { getBalance } from '@wagmi/vue/actions'
import { authApi, type AuthUser, type UpdateProfileInput, type UserRole } from '@/api/auth'
import { clearSessionState, setCsrfToken } from '@/api/client'
import { wagmiConfig, monadTestnetChain } from '@/config/wagmi'

type Signer = (message: string, account: string) => Promise<string>

export const useWalletStore = defineStore('wallet', () => {
  const connected = ref(false)
  const restored = ref(false)
  const address = ref('')
  const balance = ref(0)
  const sessionExpiresAt = ref('')

  const userProfile = ref({
    name: '',
    email: '',
    phone: '',
    role: 'customer' as UserRole,
    rating: 0,
    vehicleType: null as AuthUser['courierProfile'] extends { vehicleType: infer T } | null ? T | null : null,
  })

  const displayAddress = () =>
    address.value ? `${address.value.slice(0, 6)}...${address.value.slice(-4)}` : ''

  function applySession(payload: { user: AuthUser; session: { expiresAt: string }; csrfToken: string }) {
    const user = payload.user
    connected.value = true
    address.value = user.walletAddress
    sessionExpiresAt.value = payload.session.expiresAt
    setCsrfToken(payload.csrfToken)
    userProfile.value = {
      name: user.displayName || 'Kullanıcı',
      email: user.email || '',
      phone: user.phone || '',
      role: user.role,
      rating: 0,
      vehicleType: user.courierProfile?.vehicleType ?? null,
    }
  }

  function applyUser(user: AuthUser) {
    userProfile.value = {
      name: user.displayName || 'Kullanıcı',
      email: user.email || '',
      phone: user.phone || '',
      role: user.role,
      rating: userProfile.value.rating,
      vehicleType: user.courierProfile?.vehicleType ?? null,
    }
  }

  function clearLocalSession() {
    connected.value = false
    address.value = ''
    balance.value = 0
    sessionExpiresAt.value = ''
    userProfile.value = { name: '', email: '', phone: '', role: 'customer', rating: 0, vehicleType: null }
    clearSessionState()
  }

  async function fetchBalance() {
    if (!address.value) return
    try {
      const result = await getBalance(wagmiConfig, {
        address: address.value as `0x${string}`,
        chainId: monadTestnetChain.id,
      })
      balance.value = Number(Number(formatEther(result.value)).toFixed(4))
    } catch {
      // A transient RPC error must not destroy an otherwise valid SIWE session.
    }
  }

  async function authenticate(walletAddress: string, signer: Signer) {
    clearLocalSession()
    const challenge = await authApi.nonce(walletAddress)
    const signature = await signer(challenge.message, walletAddress)
    const session = await authApi.verify(challenge.message, signature)
    if (session.user.walletAddress.toLowerCase() !== walletAddress.toLowerCase()) {
      clearLocalSession()
      throw new Error('Oturum cüzdan adresiyle eşleşmedi')
    }
    applySession(session)
    await fetchBalance()
    return session.user
  }

  async function registerMetaMask(data: {
    walletAddress: string
    name: string
    phone: string
    role: UserRole
    signer: Signer
  }) {
    await authenticate(data.walletAddress, data.signer)
    await updateProfile({
      displayName: data.name.trim(),
      phone: data.phone.trim(),
      role: data.role,
      courierProfile: data.role === 'courier' ? { vehicleType: 'on_foot' } : null,
    })
  }

  async function updateProfile(data: UpdateProfileInput | { name?: string; phone?: string }) {
    const normalized: UpdateProfileInput = 'name' in data
      ? { displayName: data.name, phone: data.phone }
      : data
    applyUser(await authApi.updateMe(normalized))
  }

  async function disconnect() {
    try {
      if (connected.value) await authApi.logout()
    } finally {
      clearLocalSession()
    }
  }

  async function restoreSession() {
    try {
      const session = await authApi.session()
      applySession(session)
      await fetchBalance()
    } catch {
      clearLocalSession()
    } finally {
      restored.value = true
    }
  }

  function handleWalletAddressChanged(nextAddress?: string) {
    if (!connected.value || !nextAddress) return
    if (nextAddress.toLowerCase() !== address.value.toLowerCase()) {
      void disconnect()
    }
  }

  return {
    connected, restored, address, balance, sessionExpiresAt, userProfile, displayAddress,
    authenticate, registerMetaMask, updateProfile, disconnect, restoreSession, fetchBalance,
    clearLocalSession, handleWalletAddressChanged,
  }
})
