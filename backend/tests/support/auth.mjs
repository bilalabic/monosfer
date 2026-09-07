import { randomUUID } from 'node:crypto';
import { privateKeyToAccount, generatePrivateKey } from 'viem/accounts';
import { testApplication } from './app.mjs';

export const wallet = () => privateKeyToAccount(generatePrivateKey());
export const origin = 'https://app.example.com';
export function memoryStores() {
  const values = new Map();
  const users = new Map();
  const sessions = new Map();
  const redis = {
    ping: async () => true,
    async get(key) { const row = values.get(key); return row && row.expires > Date.now() ? row.value : null; },
    async set(key, value, ttl) { values.set(key, { value, expires: Date.now() + ttl * 1000 }); },
    async del(keys) { keys.forEach(key => values.delete(key)); },
    async consume(key, expected) { const row = values.get(key); if (!row || row.expires <= Date.now() || row.value !== expected) return false; values.delete(key); return true; },
    async increment(key, ttl) { const value = Number(await this.get(key) ?? 0) + 1; await this.set(key, String(value), ttl); return value; },
  };
  const authRepository = {
    async createSession(address, sessionHash, expiresAt) {
      let user = [...users.values()].find(user => user.walletAddress.toLowerCase() === address.toLowerCase());
      if (!user) { user = { id: randomUUID(), walletAddress: address, role: 'customer', displayName: null, email: null, phone: null, courierProfile: null, createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() }; users.set(user.id, user); }
      sessions.set(sessionHash, { user, expiresAt, revoked: false });
      return user;
    },
    async findSession(sessionHash) { const row = sessions.get(sessionHash); return row && !row.revoked && Date.parse(row.expiresAt) > Date.now() ? row : null; },
    async revoke(sessionHash, userId, all) { const hashes = []; for (const [key, value] of sessions) if (value.user.id === userId && !value.revoked && (all || key === sessionHash)) { value.revoked = true; hashes.push(key); } return hashes; },
  };
  const usersRepository = { async update(id, input) { for (const [key, value] of Object.entries(input)) if (value !== undefined) users.get(id)[key] = value; return users.get(id); } };
  return { redis, authRepository, usersRepository, values, users, sessions };
}
export async function authApplication(options = {}) {
  const stores = memoryStores();
  return { ...await testApplication({ ...stores, ...options }), ...stores };
}
export async function challenge(app, account = wallet(), requestOrigin = origin) {
  const result = await app.inject({ method: 'POST', url: '/v1/auth/siwe/nonce', headers: { origin: requestOrigin }, payload: { address: account.address } });
  if (result.statusCode !== 200) throw new Error(`Nonce failed: ${result.statusCode} ${result.body}`);
  return { ...result.json(), cookie: result.cookies.map(cookie => `${cookie.name}=${cookie.value}`).join('; '), account };
}
export async function verify(app, issued, changes = {}, requestOrigin = origin) {
  const message = changes.message ?? issued.message;
  return app.inject({ method: 'POST', url: '/v1/auth/siwe/verify', headers: { origin: requestOrigin, cookie: changes.cookie ?? issued.cookie },
    payload: { message, signature: changes.signature ?? await issued.account.signMessage({ message }) } });
}
export async function login(app, account = wallet(), requestOrigin = origin) {
  const issued = await challenge(app, account, requestOrigin);
  const result = await verify(app, issued, {}, requestOrigin);
  if (result.statusCode !== 200) throw new Error(`Login failed: ${result.statusCode} ${result.body}`);
  const cookie = result.cookies.find(cookie => cookie.name.includes('sid'));
  return { ...result.json(), response: result, cookie: `${cookie.name}=${cookie.value}`, rawSession: cookie.value, issued };
}
