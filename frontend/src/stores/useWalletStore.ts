import { defineStore } from 'pinia'
import { ref } from 'vue'

export const useWalletStore = defineStore('wallet', () => {
  const connected = ref(false)
  const address = ref('')
  const balance = ref(0)
  
  // User Profile
  const userProfile = ref({
    name: '',
    email: '',
    phone: '',
    role: 'customer' as 'customer' | 'courier',
    rating: 0
  })

  const displayAddress = () =>
    address.value ? `${address.value.slice(0, 6)}...${address.value.slice(-4)}` : ''

  function connect(email = 'test@example.com', phone = '') {
    connected.value = true
    address.value = '0x71C7656EC7ab88b098defB751B7401B5f6d8976F'
    balance.value = 248.5
    userProfile.value = {
      name: 'Yusuf Arslan',
      email,
      phone: phone || '+90 555 123 4567',
      role: 'customer',
      rating: 4.8
    }
  }

  function register(data: { name: string; email: string; phone: string; role: 'customer' | 'courier' }) {
    connected.value = true
    address.value = '0xNewWalletAddress123456789'
    balance.value = 50.0 // welcome bonus
    userProfile.value = {
      ...data,
      rating: 0
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
  }

  return { connected, address, balance, userProfile, displayAddress, connect, register, updateProfile, disconnect }
})
