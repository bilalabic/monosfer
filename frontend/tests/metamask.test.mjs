import test from 'node:test'
import assert from 'node:assert/strict'
import { EventEmitter } from 'node:events'
import { fileURLToPath } from 'node:url'
import { createJiti } from 'jiti'

const jiti = createJiti(import.meta.url, {
  alias: { '@': fileURLToPath(new URL('../app', import.meta.url)) },
})
// Load the actual composable and connector configuration without a browser or RPC.
const { useMetaMask } = await jiti.import('../app/composables/useMetaMask.ts')
const { wagmiConfig } = await jiti.import('../app/config/wagmi.ts')
const { createRenderer, h, nextTick } = await jiti.import('vue')
const { WagmiPlugin } = await jiti.import('@wagmi/vue')
const { VueQueryPlugin, QueryClient } = await jiti.import('@tanstack/vue-query')

const address = '0x0000000000000000000000000000000000000001'
const chainId = '0x27a3'
let provider
const renderer = createRenderer({
  createElement: () => ({}), createText: () => ({}), createComment: () => ({}),
  insert() {}, remove() {}, setText() {}, setElementText() {}, patchProp() {},
  parentNode: () => null, nextSibling: () => null,
})

async function fixture(t) {
  const calls = []
  provider = new EventEmitter()
  provider.isMetaMask = true
  let activeChain = chainId
  let failure
  provider.request = async ({ method, params }) => {
    calls.push(method)
    if (failure && (method === failure.method || (failure.method === 'wallet_requestPermissions' && method === 'eth_requestAccounts'))) throw failure.error
    if (method === 'wallet_requestPermissions') return [{ caveats: [{ value: [address] }] }]
    if (method === 'eth_accounts' || method === 'eth_requestAccounts') return [address]
    if (method === 'eth_chainId') return activeChain
    if (method === 'wallet_switchEthereumChain') { activeChain = params[0].chainId; return null }
    if (method === 'personal_sign') return `0x${'1'.repeat(130)}`
    throw new Error(`Unexpected wallet method: ${method}`)
  }
  globalThis.window = { ethereum: provider }
  globalThis.document = { cookie: '' }
  const queryClient = new QueryClient({ defaultOptions: { mutations: { retry: false } } })
  let wallet
  let initialInstalled
  const app = renderer.createApp({
    setup() {
      wallet = useMetaMask()
      initialInstalled = wallet.isInstalled.value
      return () => h('div')
    },
  })
  app.use(WagmiPlugin, { config: wagmiConfig, reconnectOnMount: false })
  app.use(VueQueryPlugin, { queryClient })
  app.mount({})
  await nextTick()
  await new Promise(resolve => setImmediate(resolve))
  t.after(() => {
    app.unmount()
    queryClient.clear()
    wagmiConfig.setState(state => ({ ...state, current: null, connections: new Map(), status: 'disconnected' }))
    delete globalThis.window
    delete globalThis.document
  })
  return { wallet, calls, initialInstalled, fail: (error, method = 'wallet_requestPermissions') => { failure = error ? { error, method } : undefined }, setChain: value => { activeChain = value } }
}

test('installed extension connects without the optional SDK and remains SSR-safe', async t => {
  const { wallet, calls, initialInstalled } = await fixture(t)
  assert.equal(initialInstalled, false)
  assert.equal(wallet.isInstalled.value, true)
  assert.deepEqual(await wallet.connect(), { address })
  assert.ok(calls.includes('wallet_requestPermissions'))
  assert.equal(wallet.error.value, null)
})

test('retry after rejected SIWE signing reuses the existing connection', async t => {
  const { wallet, calls, fail } = await fixture(t)
  assert.deepEqual(await wallet.connect(), { address })
  fail(Object.assign(new Error('User rejected signing'), { code: 4001 }), 'personal_sign')
  await assert.rejects(wallet.signMessage('Local sign-in test', address))
  assert.equal(wallet.error.value, 'user_rejected')
  fail(undefined)
  const permissionsBeforeRetry = calls.filter(method => method === 'wallet_requestPermissions').length
  assert.deepEqual(await wallet.connect(), { address })
  assert.equal(calls.filter(method => method === 'wallet_requestPermissions').length, permissionsBeforeRetry)
  assert.equal(wallet.error.value, null)
})

test('wrong network switches to Monad testnet before returning the account', async t => {
  const { wallet, calls, setChain } = await fixture(t)
  setChain('0x1')
  assert.deepEqual(await wallet.connect(), { address })
  assert.ok(calls.includes('wallet_switchEthereumChain'))
})

test('wrapped rejection and pending requests have actionable messages and allow retry', async t => {
  const { wallet, fail } = await fixture(t)
  for (const [code, expected] of [[4001, 'user_rejected'], [-32002, 'request_pending']]) {
    fail(Object.assign(new Error('Wallet request failed'), { code }))
    assert.equal(await wallet.connect(), null)
    assert.equal(wallet.error.value, expected)
    assert.ok(wallet.errorMessage.value)
    assert.equal(wallet.connecting.value, false)
  }
  fail(undefined)
  assert.deepEqual(await wallet.connect(), { address })
})
