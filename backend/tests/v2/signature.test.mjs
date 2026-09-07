import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { SiweMessage } from '@signinwithethereum/siwe';
import { hashMessage } from 'viem';
import { ConfigService, parseSettings } from '../../dist/config/config.js';
import { SignatureService } from '../../dist/auth/signature.service.js';
import { testEnv } from '../support/app.mjs';
import { wallet } from '../support/auth.mjs';

function messageFor(account, overrides = {}) {
  return new SiweMessage({ domain: testEnv.SIWE_DOMAIN, uri: testEnv.SIWE_URI, address: account.address,
    version: '1', chainId: 10143, nonce: '0123456789abcdef', statement: testEnv.SIWE_STATEMENT,
    issuedAt: new Date().toISOString(), expirationTime: new Date(Date.now() + 60000).toISOString(), ...overrides });
}

test('SIWE library strictly verifies EOA signature, domain, URI, chain, nonce and timestamps', async () => {
  const service = new SignatureService(new ConfigService(parseSettings(testEnv)));
  const account = wallet();
  const good = messageFor(account);
  assert.equal(await service.verify(good, await account.signMessage({ message: good.prepareMessage() }), good.nonce), true);
  for (const change of [{ domain: 'evil.example.com' }, { uri: 'https://evil.example.com' }, { chainId: 1 }, { expirationTime: '2000-01-01T00:00:00.000Z' }, { notBefore: new Date(Date.now() + 60000).toISOString() }]) {
    const message = messageFor(account, change);
    assert.equal(await service.verify(message, await account.signMessage({ message: message.prepareMessage() }), message.nonce), false);
  }
  assert.equal(await service.verify(good, await account.signMessage({ message: good.prepareMessage() }), 'anothernonce123'), false);
});

test('ERC-1271 uses actual RPC chain ID and read-only signature check; rejects invalid, wrong-chain and RPC failures', async t => {
  const calls = [];
  let chain = '0x279f'; // 10143
  let valid = true;
  let unavailable = false;
  const server = createServer(async (request, response) => {
    let body = ''; for await (const chunk of request) body += chunk;
    const rpc = JSON.parse(body); calls.push(rpc);
    response.setHeader('content-type', 'application/json');
    if (unavailable) { response.statusCode = 503; response.end('{}'); return; }
    response.end(JSON.stringify({ jsonrpc: '2.0', id: rpc.id, result: rpc.method === 'eth_chainId' ? chain : `0x${valid ? '1626ba7e' : 'ffffffff'}${'0'.repeat(56)}` }));
  });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => { server.closeAllConnections(); return new Promise(resolve => server.close(resolve)); });
  const settings = parseSettings({ ...testEnv, SIWE_RPC_URL: `http://127.0.0.1:${server.address().port}`, CONNECTION_TIMEOUT_MS: '100' });
  const service = new SignatureService(new ConfigService(settings));
  const message = messageFor(wallet());
  const signature = '0x1234';
  assert.equal(await service.verify(message, signature, message.nonce), true);
  assert.deepEqual(calls.map(call => call.method), ['eth_chainId', 'eth_call']);
  assert.equal(calls[1].params[0].to.toLowerCase(), message.address.toLowerCase());
  assert.ok(calls[1].params[0].data.includes(hashMessage(message.prepareMessage()).slice(2)));
  valid = false;
  assert.equal(await service.verify(message, signature, message.nonce), false);
  const before = calls.filter(call => call.method === 'eth_call').length;
  chain = '0x1';
  assert.equal(await service.verify(message, signature, message.nonce), false);
  assert.equal(calls.filter(call => call.method === 'eth_call').length, before);
  unavailable = true;
  assert.equal(await service.verify(message, signature, message.nonce), false);
});
