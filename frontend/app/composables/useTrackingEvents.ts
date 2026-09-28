import { ref } from 'vue'
import type { TrackingLocationData } from '@/api/tracking'

export type TrackingSseEvent =
  | { type: 'location'; payload: { eventId: string; location: TrackingLocationData | null } }
  | { type: 'reset'; payload: TrackingLocationData | null }
  | { type: 'closed'; payload: { reason: string } }

export type TrackingSseStatus = 'connecting' | 'open' | 'reconnecting' | 'stopped' | 'denied'

interface ParsedSseMessage {
  event: string
  data: string
  id?: string
}

function parseSseBlock(block: string): ParsedSseMessage | null {
  let event = 'message'
  let data = ''
  let id: string | undefined
  for (const line of block.split('\n')) {
    if (!line || line.startsWith(':')) continue
    const idx = line.indexOf(':')
    const field = idx === -1 ? line : line.slice(0, idx)
    const value = idx === -1 ? '' : line.slice(idx + 1).replace(/^ /, '')
    if (field === 'event') event = value
    else if (field === 'data') data += (data ? '\n' : '') + value
    else if (field === 'id') id = value
  }
  if (!data) return null
  return { event, data, id }
}

const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms))

/**
 * Consumes the delivery tracking SSE stream. Native EventSource can't send the
 * required `x-tracking-session` header, so this reads the fetch stream by hand.
 */
export function useTrackingEvents() {
  let controller: AbortController | null = null
  let stopped = true
  let lastEventId = ''
  const status = ref<TrackingSseStatus>('stopped')

  async function readStream(body: ReadableStream<Uint8Array>, onEvent: (event: TrackingSseEvent) => void) {
    const reader = body.getReader()
    const decoder = new TextDecoder()
    let buffer = ''
    status.value = 'open'
    while (true) {
      const { done, value } = await reader.read()
      if (done) return
      buffer += decoder.decode(value, { stream: true })
      let sepIndex: number
      while ((sepIndex = buffer.indexOf('\n\n')) !== -1) {
        const block = buffer.slice(0, sepIndex)
        buffer = buffer.slice(sepIndex + 2)
        const parsed = parseSseBlock(block)
        if (!parsed) continue
        if (parsed.id) lastEventId = parsed.id
        if (parsed.event === 'location' || parsed.event === 'reset' || parsed.event === 'closed') {
          try {
            onEvent({ type: parsed.event, payload: JSON.parse(parsed.data) } as TrackingSseEvent)
          } catch {
            // Malformed frame — drop it, keep the stream alive.
          }
        }
      }
    }
  }

  async function connect(deliveryId: string, token: string, onEvent: (event: TrackingSseEvent) => void) {
    stopped = false
    let retryDelayMs = 1000
    const base = String(useRuntimeConfig().public.apiBase).replace(/\/$/, '')
    const absoluteBase = import.meta.server && base.startsWith('/') ? `${useRequestURL().origin}${base}` : base
    const url = `${absoluteBase}/deliveries/${deliveryId}/tracking/events`

    while (!stopped) {
      status.value = controller ? 'reconnecting' : 'connecting'
      controller = new AbortController()
      try {
        const response = await fetch(url, {
          credentials: 'include',
          headers: {
            'x-tracking-session': token,
            ...(lastEventId ? { 'Last-Event-ID': lastEventId } : {}),
          },
          signal: controller.signal,
        })
        if (response.status === 401 || response.status === 403) {
          status.value = 'denied'
          return
        }
        if (!response.ok || !response.body) {
          throw new Error(`Tracking akışı başarısız: ${response.status}`)
        }
        retryDelayMs = 1000
        await readStream(response.body, onEvent)
      } catch (error) {
        if (stopped || (error instanceof DOMException && error.name === 'AbortError')) return
      }
      if (stopped) return
      await sleep(retryDelayMs + Math.random() * 300)
      retryDelayMs = Math.min(retryDelayMs * 2, 15000)
    }
  }

  function stop() {
    stopped = true
    controller?.abort()
    controller = null
    status.value = 'stopped'
  }

  return { status, connect, stop }
}
