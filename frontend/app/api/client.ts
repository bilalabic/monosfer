let csrfToken = ''

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly code?: string,
    readonly requestId?: string,
    readonly retryAfter?: number,
  ) {
    super(message)
    this.name = 'ApiError'
  }
}

export function setCsrfToken(token?: string | null) {
  csrfToken = token ?? ''
}

export function clearSessionState() {
  csrfToken = ''
}

export function createIdempotencyKey() {
  if (typeof crypto === 'undefined' || !crypto.randomUUID) {
    throw new Error('Güvenli istek kimliği üretilemedi')
  }
  return crypto.randomUUID()
}

interface ApiOptions {
  headers?: Record<string, string>
  idempotencyKey?: string
  signal?: AbortSignal
}

async function request<T>(path: string, init: RequestInit = {}, options: ApiOptions = {}): Promise<T> {
  const base = String(useRuntimeConfig().public.apiBase).replace(/\/$/, '')
  const absoluteBase = import.meta.server && base.startsWith('/') ? `${useRequestURL().origin}${base}` : base
  const method = (init.method ?? 'GET').toUpperCase()
  const mutating = !['GET', 'HEAD', 'OPTIONS'].includes(method)
  const response = await fetch(`${absoluteBase}${path}`, {
    ...init,
    credentials: 'include',
    signal: options.signal,
    headers: {
      ...(init.body !== undefined ? { 'Content-Type': 'application/json' } : {}),
      ...(mutating && csrfToken ? { 'x-csrf-token': csrfToken } : {}),
      ...(options.idempotencyKey ? { 'Idempotency-Key': options.idempotencyKey } : {}),
      ...options.headers,
    },
  })

  if (!response.ok) {
    const payload = await response.json().catch(() => ({})) as {
      error?: { code?: string; message?: string; requestId?: string }
    }
    if (response.status === 401) {
      clearSessionState()
      if (typeof window !== 'undefined') window.dispatchEvent(new CustomEvent('monosfer:unauthorized'))
    }
    const retryAfter = Number(response.headers.get('retry-after'))
    throw new ApiError(
      payload.error?.message || response.statusText || 'API isteği başarısız oldu',
      response.status,
      payload.error?.code,
      payload.error?.requestId,
      Number.isFinite(retryAfter) ? retryAfter : undefined,
    )
  }

  if (response.status === 204) return undefined as T
  return response.json() as Promise<T>
}

export const api = {
  get: <T>(path: string, options?: ApiOptions) => request<T>(path, {}, options),
  post: <T>(path: string, body: unknown, options?: ApiOptions) =>
    request<T>(path, { method: 'POST', body: JSON.stringify(body) }, options),
  patch: <T>(path: string, body: unknown, options?: ApiOptions) =>
    request<T>(path, { method: 'PATCH', body: JSON.stringify(body) }, options),
  delete: <T = void>(path: string, options?: ApiOptions) =>
    request<T>(path, { method: 'DELETE' }, options),
}
