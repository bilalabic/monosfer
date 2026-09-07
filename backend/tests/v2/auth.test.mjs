import test from 'node:test';
import assert from 'node:assert/strict';
import { authApplication, challenge, login, verify, wallet, origin } from '../support/auth.mjs';
import { hash } from '../../dist/security/tokens.js';
import { ServiceUnavailableException } from '@nestjs/common';

test('SIWE sign-in, cookie attributes, public schemas, profile isolation and validation', async t => {
  const { app, document, logs, users, sessions, values } = await authApplication(); t.after(() => app.close());
  const first = await login(app);
  assert.equal(first.user.role, 'customer');
  assert.equal(users.size, 1);
  const header = first.response.headers['set-cookie'].find(value => value.startsWith('__Host-monosfer_sid='));
  for (const attribute of ['HttpOnly', 'Secure', 'SameSite=Lax', 'Path=/']) assert.ok(header.includes(attribute));
  assert.ok(!header.includes('Domain='));
  assert.ok(sessions.has(hash(first.rawSession)));
  assert.ok(!JSON.stringify([...values]).includes(first.rawSession));
  const session = await app.inject({ url: '/v1/auth/session', headers: { cookie: first.cookie } });
  assert.deepEqual(session.json(), { user: first.user, session: first.session, csrfToken: first.csrfToken });
  const headers = { cookie: first.cookie, origin, 'x-csrf-token': first.csrfToken };
  const patch = await app.inject({ method: 'PATCH', url: '/v1/users/me', headers, payload: { displayName: 'Test User', email: 'private@example.com', phone: '+905551234567', role: 'courier', courierProfile: { vehicleType: 'bicycle' } } });
  assert.equal(patch.statusCode, 200);
  assert.equal(patch.json().role, 'courier');
  for (const payload of [{ role: 'admin' }, { role: null }, { walletAddress: wallet().address }, { id: first.user.id }, { email: 'invalid' }, { phone: '123' }, { courierProfile: { vehicleType: 'car', approved: true } }, { courierProfile: {} }, { courierProfile: [] }, { displayName: 4 }]) {
    assert.equal((await app.inject({ method: 'PATCH', url: '/v1/users/me', headers, payload })).statusCode, 400);
  }
  const other = await login(app);
  assert.notEqual(other.user.id, first.user.id);
  assert.equal((await app.inject({ url: '/v1/users/me', headers: { cookie: other.cookie } })).json().displayName, null);
  assert.equal((await app.inject({ method: 'PATCH', url: '/v1/users/me', headers, payload: { email: null, phone: null, courierProfile: null } })).statusCode, 200);
  assert.ok(document.paths['/v1/users/me'].patch.requestBody);
  assert.ok(document.components.schemas.SessionResponseDto);
  for (const key of ['displayName', 'email', 'phone']) assert.equal(document.components.schemas.UpdateUserDto.properties[key].type, 'string');
  assert.equal(document.components.schemas.UpdateUserDto.additionalProperties, false);
  for (const secret of [first.rawSession, first.csrfToken, first.issued.nonce, first.issued.message, 'private@example.com', '+905551234567']) assert.ok(!logs.join('').includes(secret));
});

test('missing auth, Origin and CSRF are rejected; tokens are session-bound', async t => {
  const { app } = await authApplication(); t.after(() => app.close());
  for (const url of ['/v1/auth/session', '/v1/users/me']) assert.equal((await app.inject(url)).statusCode, 401);
  for (const url of ['/v1/auth/session', '/v1/auth/sessions']) assert.equal((await app.inject({ method: 'DELETE', url })).statusCode, 401);
  assert.equal((await app.inject({ method: 'PATCH', url: '/v1/users/me', payload: {} })).statusCode, 401);
  for (const invalidOrigin of [undefined, 'null', 'https://evil.example.com']) {
    const headers = invalidOrigin ? { origin: invalidOrigin } : {};
    assert.equal((await app.inject({ method: 'POST', url: '/v1/auth/siwe/nonce', headers, payload: { address: wallet().address } })).statusCode, 403);
  }
  const a = await login(app); const b = await login(app);
  for (const csrfToken of [undefined, 'wrong', b.csrfToken]) {
    const headers = { cookie: a.cookie, origin, ...(csrfToken ? { 'x-csrf-token': csrfToken } : {}) };
    for (const url of ['/v1/auth/session', '/v1/auth/sessions']) assert.equal((await app.inject({ method: 'DELETE', url, headers })).statusCode, 403);
    assert.equal((await app.inject({ method: 'PATCH', url: '/v1/users/me', headers, payload: { role: 'courier' } })).statusCode, 403);
  }
});

test('invalid address, domain/URI/chain/expiry, altered message and wrong signer fail', async t => {
  const { app, values } = await authApplication(); t.after(() => app.close());
  assert.equal((await app.inject({ method: 'POST', url: '/v1/auth/siwe/nonce', headers: { origin }, payload: { address: '0x123' } })).statusCode, 400);
  const issued = await challenge(app);
  for (const message of [issued.message.replace('app.example.com', 'evil.example.com'), issued.message.replace('Chain ID: 10143', 'Chain ID: 1'), issued.message.replace('URI: https://app.example.com', 'URI: https://evil.example.com'), issued.message.replace(issued.expiresAt, '2000-01-01T00:00:00.000Z'), issued.message.replace('Sign in to Monosfer.', 'Different statement.'), 'malformed']) {
    assert.equal((await verify(app, issued, { message })).statusCode, 401);
  }
  assert.equal((await verify(app, issued, { cookie: '' })).statusCode, 401);
  const another = await challenge(app);
  assert.equal((await verify(app, issued, { cookie: another.cookie })).statusCode, 401);
  assert.equal((await verify(app, issued, { signature: await wallet().signMessage({ message: issued.message }) })).statusCode, 401);
  values.get(`auth:nonce:${hash(issued.nonce)}`).expires = Date.now() - 1;
  assert.equal((await verify(app, issued)).statusCode, 401);
});

test('concurrent nonce replay creates exactly one session', async t => {
  const { app, sessions } = await authApplication(); t.after(() => app.close());
  const issued = await challenge(app);
  const responses = await Promise.all([verify(app, issued), verify(app, issued)]);
  assert.deepEqual(responses.map(r => r.statusCode).sort(), [200, 401]);
  assert.equal(sessions.size, 1);
  assert.equal((await verify(app, issued)).statusCode, 401);
});

test('logout and revoke-all invalidate old cookies, preserve other users and fail closed with stale cache', async t => {
  const { app, values, sessions } = await authApplication(); t.after(() => app.close());
  const account = wallet();
  const a = await login(app, account); const b = await login(app, account); const other = await login(app);
  const headers = { cookie: a.cookie, origin, 'x-csrf-token': a.csrfToken };
  const result = await app.inject({ method: 'DELETE', url: '/v1/auth/session', headers });
  assert.equal(result.statusCode, 204);
  assert.ok(result.headers['set-cookie'].includes('Expires=Thu, 01 Jan 1970'));
  values.set(`auth:session:${hash(a.rawSession)}`, { value: a.user.id, expires: Date.now() + 60000 });
  assert.equal((await app.inject({ url: '/v1/auth/session', headers: { cookie: a.cookie } })).statusCode, 401);
  assert.equal((await app.inject({ url: '/v1/auth/session', headers: { cookie: b.cookie } })).statusCode, 200);
  const c = await login(app, account);
  assert.equal((await app.inject({ method: 'DELETE', url: '/v1/auth/sessions', headers: { cookie: b.cookie, origin, 'x-csrf-token': b.csrfToken } })).statusCode, 204);
  for (const session of [a, b, c]) assert.equal((await app.inject({ url: '/v1/users/me', headers: { cookie: session.cookie } })).statusCode, 401);
  assert.equal((await app.inject({ url: '/v1/users/me', headers: { cookie: other.cookie } })).statusCode, 200);
  sessions.get(hash(other.rawSession)).expiresAt = '2000-01-01T00:00:00.000Z';
  assert.equal((await app.inject({ url: '/v1/users/me', headers: { cookie: other.cookie } })).statusCode, 401);
});

test('rate limit covers malformed requests and ignores spoofed forwarded IP', async t => {
  const { app } = await authApplication({ env: { AUTH_RATE_LIMIT_MAX: '2' } }); t.after(() => app.close());
  const request = ip => app.inject({ method: 'POST', url: '/v1/auth/siwe/nonce', headers: { origin, 'x-forwarded-for': ip }, payload: { address: 'invalid' } });
  assert.equal((await request('1.1.1.1')).statusCode, 400);
  assert.equal((await request('2.2.2.2')).statusCode, 400);
  const limited = await request('3.3.3.3');
  assert.equal(limited.statusCode, 429); assert.equal(limited.json().error.code, 'TOO_MANY_REQUESTS');
  assert.equal(limited.headers['retry-after'], '60');
});

test('browser preflight permits credentialed PATCH/DELETE with CSRF headers', async t => {
  const { app } = await authApplication(); t.after(() => app.close());
  for (const method of ['PATCH', 'DELETE']) {
    const result = await app.inject({ method: 'OPTIONS', url: '/v1/users/me', headers: { origin, 'access-control-request-method': method, 'access-control-request-headers': 'content-type,x-csrf-token' } });
    assert.equal(result.statusCode, 204);
    assert.ok(result.headers['access-control-allow-methods'].includes(method));
    assert.ok(result.headers['access-control-allow-headers'].includes('x-csrf-token'));
    assert.equal(result.headers['access-control-allow-credentials'], 'true');
  }
});

test('HTTP development uses usable unprefixed cookies', async t => {
  const localOrigin = 'http://localhost:3000';
  const { app } = await authApplication({ env: { NODE_ENV: 'development', SIWE_DOMAIN: 'localhost:3000', SIWE_URI: localOrigin, CORS_ORIGINS: localOrigin } }); t.after(() => app.close());
  const session = await login(app, wallet(), localOrigin);
  assert.ok(session.cookie.startsWith('monosfer_sid_dev='));
  const header = session.response.headers['set-cookie'].find(value => value.startsWith('monosfer_sid_dev='));
  assert.ok(header.includes('HttpOnly')); assert.ok(!header.includes('Secure'));
});

test('failed Redis session publication revokes SQL audit and never issues cookie', async t => {
  const { app, redis, sessions } = await authApplication(); t.after(() => app.close());
  const issued = await challenge(app);
  const originalSet = redis.set.bind(redis);
  redis.set = async (key, ...args) => { if (key.startsWith('auth:session:')) throw new ServiceUnavailableException(); return originalSet(key, ...args); };
  const result = await verify(app, issued);
  assert.equal(result.statusCode, 503);
  assert.equal(result.headers['set-cookie'], undefined);
  assert.equal(sessions.size, 1); assert.ok([...sessions.values()].every(row => row.revoked));
  assert.equal((await verify(app, issued)).statusCode, 401);
});
