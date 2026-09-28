import { ref } from 'vue'
import { defineStore } from 'pinia'
import { ApiError } from '@/api/client'

export type SupportAccessState = 'unknown' | 'checking' | 'granted' | 'unauthenticated' | 'denied' | 'disabled'

export const useSupportStore = defineStore('support', () => {
  const accessState = ref<SupportAccessState>('unknown')

  function markChecking() {
    accessState.value = 'checking'
  }

  function markGranted() {
    accessState.value = 'granted'
  }

  function resolveAccessError(error: unknown) {
    if (error instanceof ApiError) {
      if (error.status === 401) accessState.value = 'unauthenticated'
      else if (error.status === 403) accessState.value = 'denied'
      else if (error.status === 503) accessState.value = 'disabled'
      else accessState.value = 'denied'
      return
    }
    accessState.value = 'denied'
  }

  return { accessState, markChecking, markGranted, resolveAccessError }
})
