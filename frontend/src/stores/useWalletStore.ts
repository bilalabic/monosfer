import { defineStore } from 'pinia'
import { ref } from 'vue'

export const useWalletStore = defineStore('wallet', () => {
  const connected = ref(false)
  const address = ref('')
  const balance = ref(0)
  const displayAddress = () =>
    address.value ? `${address.value.slice(0, 6)}...${address.value.slice(-4)}` : ''

  function connect() {
    // Simulate wallet connection
    connected.value = true
    address.value = '0x71C7656EC7ab88b098defB751B7401B5f6d8976F'
    balance.value = 248.5
  }

  function disconnect() {
    connected.value = false
    address.value = ''
    balance.value = 0
  }

  return { connected, address, balance, displayAddress, connect, disconnect }
})
