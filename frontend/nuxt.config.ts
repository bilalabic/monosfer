import tailwindcss from '@tailwindcss/vite'

const backendOrigin = process.env.NUXT_BACKEND_ORIGIN || 'http://127.0.0.1:3001'
const realtimeOrigin = process.env.NUXT_REALTIME_ORIGIN || 'http://127.0.0.1:3002'

// https://nuxt.com/docs/api/configuration/nuxt-config
export default defineNuxtConfig({
  compatibilityDate: '2026-08-19',
  future: {
    // Nuxt 5 is still in development — do not opt in yet (DEC-025 / 18.1.1).
  },
  devtools: { enabled: true },

  srcDir: 'app/',

  modules: ['@pinia/nuxt', '@vite-pwa/nuxt'],

  // shadcn-vue's ui/*/index.ts barrel files aren't components themselves —
  // without this, Nuxt's auto-scanner collides them with the .vue file
  // they re-export (e.g. ui/button/index.ts and ui/button/Button.vue both
  // resolving to <UiButton>).
  components: [{ path: '~/components', extensions: ['vue'] }],

  css: ['~/assets/main.css'],

  vite: {
    plugins: [tailwindcss()],
  },

  runtimeConfig: {
    // Server-only: the tracking SSE stream is served by a separate realtime
    // process, proxied same-origin by server/middleware/tracking-events-proxy.ts.
    realtimeOrigin,
    public: {
      // V2 is intentionally a separate, same-origin /v1 surface. There is no
      // legacy /api fallback because its JWT and delivery state semantics differ.
      apiBase: process.env.NUXT_PUBLIC_API_BASE || '/v1',
    },
  },

  // Wallet auth state only exists client-side, so these routes are gated by
  // app/middleware/auth.global.ts *after* hydration. If the server rendered
  // their real content, an unconnected visitor would briefly see it before
  // the redirect fires, and Vue would hit a hydration mismatch tearing that
  // content down. ssr:false skips the server render entirely for them —
  // note this must be a routeRule, NOT `definePageMeta({ ssr: false })`,
  // which is not a recognized page-meta key.
  routeRules: {
    '/v1/**': { proxy: `${backendOrigin}/v1/**` },
    '/dashboard': { ssr: false },
    '/create': { ssr: false },
    '/payment/**': { ssr: false },
    '/courier/receive/**': { ssr: false },
    '/kuryem-nerede': { ssr: false },
    '/map': { ssr: false }, // Leaflet also needs `window`
    '/support/**': { ssr: false },
  },

  app: {
    head: {
      htmlAttrs: { lang: 'tr' },
      title: 'Delivera — Merkeziyetsiz Teslimat Ağı',
      meta: [
        { name: 'viewport', content: 'width=device-width, initial-scale=1.0' },
        {
          name: 'description',
          content:
            'Delivera — Merkeziyetsiz, güvenli ve rekabetçi teslimat ağı. Monad blockchain üzerinde escrow ödemeli kurye platformu.',
        },
        { name: 'theme-color', content: '#f97316' },
      ],
      link: [
        { rel: 'icon', href: '/favicon.ico', sizes: '32x32' },
        { rel: 'icon', type: 'image/png', sizes: '16x16', href: '/favicon-16x16.png' },
        { rel: 'icon', type: 'image/png', sizes: '32x32', href: '/favicon-32x32.png' },
        { rel: 'icon', type: 'image/png', sizes: '48x48', href: '/favicon-48x48.png' },
        { rel: 'apple-touch-icon', sizes: '180x180', href: '/apple-touch-icon.png' },
        { rel: 'manifest', href: '/site.webmanifest' },
        { rel: 'preconnect', href: 'https://fonts.googleapis.com' },
        { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' },
        {
          rel: 'stylesheet',
          href: 'https://fonts.googleapis.com/css2?family=Inter:ital,opsz,wght@0,14..32,300;0,14..32,400;0,14..32,500;0,14..32,600;0,14..32,700;0,14..32,800;1,14..32,400&family=Space+Grotesk:wght@500;600;700&display=swap',
        },
      ],
    },
  },

  typescript: {
    typeCheck: false,
  },

  pwa: {
    registerType: 'autoUpdate',
    // Reuse the hand-written public/site.webmanifest + existing favicons as-is.
    manifest: false,
    workbox: {
      navigateFallback: '/',
      // NFR-PWA-001: never let the service worker serve stale auth/financial/
      // tracking data — every backend call bypasses the cache entirely.
      runtimeCaching: [
        {
          urlPattern: ({ url }) => url.pathname.startsWith('/v1/'),
          handler: 'NetworkOnly',
        },
        {
          urlPattern: /\.(?:png|jpg|jpeg|svg|webp|gif|ico)$/,
          handler: 'CacheFirst',
          options: {
            cacheName: 'delivera-images',
            expiration: { maxEntries: 100, maxAgeSeconds: 60 * 60 * 24 * 30 },
          },
        },
        {
          urlPattern: /\.(?:woff2?|ttf|eot)$/,
          handler: 'CacheFirst',
          options: {
            cacheName: 'delivera-fonts',
            expiration: { maxEntries: 30, maxAgeSeconds: 60 * 60 * 24 * 365 },
          },
        },
      ],
    },
    client: {
      installPrompt: true,
    },
    devOptions: {
      // Service worker only in production builds — keep `nuxt dev` free of SW noise/caching.
      enabled: false,
    },
  },
})
