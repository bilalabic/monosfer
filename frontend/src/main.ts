import './assets/main.css'

import { createApp } from 'vue'
import { createPinia } from 'pinia'
import { autoAnimatePlugin } from '@formkit/auto-animate/vue'
import { MotionPlugin } from '@vueuse/motion'

import App from './App.vue'
import router from './router'

const app = createApp(App)
const pinia = createPinia()

app.use(pinia)
app.use(router)
app.use(autoAnimatePlugin)
app.use(MotionPlugin)

app.mount('#app')

// Restore auth session after Pinia is ready
import { useWalletStore } from './stores/useWalletStore'
useWalletStore().restoreSession()
