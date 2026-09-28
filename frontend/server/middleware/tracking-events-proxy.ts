import { defineEventHandler, proxyRequest, getRequestURL } from 'h3'

// Nitro `routeRules` proxy globs only support a trailing `**` catch-all, so a
// mid-path pattern like `/v1/deliveries/**/tracking/events` isn't reliable.
// The SSE stream is also served by a separate realtime process (not the main
// `/v1` backend), so it needs its own target origin regardless.
const TRACKING_EVENTS_PATH = /^\/v1\/deliveries\/[^/]+\/tracking\/events$/

export default defineEventHandler((event) => {
  const url = getRequestURL(event)
  if (!TRACKING_EVENTS_PATH.test(url.pathname)) return

  const config = useRuntimeConfig(event)
  return proxyRequest(event, `${config.realtimeOrigin}${url.pathname}${url.search}`)
})
