import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setPassword, completePasswordSetup } from '../api.js';

const BASE = 'https://example.supabase.co';
const KEY = 'anon-key';

// Minimal stand-in for the parts of fetch's Response that api.js touches.
function fakeFetch({ ok = true, status = 200, body = {} } = {}) {
  const calls = [];
  const impl = async (url, options) => {
    calls.push({ url, options });
    return {
      ok,
      status,
      json: async () => body,
    };
  };
  impl.calls = calls;
  return impl;
}

test('setPassword PUTs to /auth/v1/user with both auth headers', async () => {
  const fetchImpl = fakeFetch();

  await setPassword({
    supabaseUrl: BASE,
    anonKey: KEY,
    accessToken: 'token-1',
    password: 'secret123',
    fetchImpl,
  });

  assert.equal(fetchImpl.calls.length, 1);
  const { url, options } = fetchImpl.calls[0];
  assert.equal(url, `${BASE}/auth/v1/user`);
  assert.equal(options.method, 'PUT');
  assert.equal(options.headers.apikey, KEY);
  assert.equal(options.headers.Authorization, 'Bearer token-1');
  assert.deepEqual(JSON.parse(options.body), { password: 'secret123' });
});

test('setPassword throws the API message on failure', async () => {
  const fetchImpl = fakeFetch({ ok: false, status: 422, body: { msg: 'Password is too short' } });

  await assert.rejects(
    () => setPassword({
      supabaseUrl: BASE,
      anonKey: KEY,
      accessToken: 'token-1',
      password: 'x',
      fetchImpl,
    }),
    /Password is too short/,
  );
});

test('setPassword falls back to a status message when the body is not JSON', async () => {
  const fetchImpl = async () => ({
    ok: false,
    status: 500,
    json: async () => { throw new Error('not json'); },
  });

  await assert.rejects(
    () => setPassword({
      supabaseUrl: BASE,
      anonKey: KEY,
      accessToken: 'token-1',
      password: 'secret123',
      fetchImpl,
    }),
    /Request failed \(500\)/,
  );
});

test('completePasswordSetup POSTs to the RPC endpoint', async () => {
  const fetchImpl = fakeFetch();

  await completePasswordSetup({
    supabaseUrl: BASE,
    anonKey: KEY,
    accessToken: 'token-2',
    fetchImpl,
  });

  assert.equal(fetchImpl.calls.length, 1);
  const { url, options } = fetchImpl.calls[0];
  assert.equal(url, `${BASE}/rest/v1/rpc/complete_password_setup`);
  assert.equal(options.method, 'POST');
  assert.equal(options.headers.apikey, KEY);
  assert.equal(options.headers.Authorization, 'Bearer token-2');
});

test('completePasswordSetup throws on failure', async () => {
  const fetchImpl = fakeFetch({ ok: false, status: 401, body: { message: 'JWT expired' } });

  await assert.rejects(
    () => completePasswordSetup({
      supabaseUrl: BASE,
      anonKey: KEY,
      accessToken: 'token-2',
      fetchImpl,
    }),
    /JWT expired/,
  );
});
