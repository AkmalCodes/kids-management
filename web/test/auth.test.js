import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseAuthFragment, parseAuthParams, validatePassword, createSessionProvider } from '../auth.js';

test('parseAuthFragment reads an invite token', () => {
  const result = parseAuthFragment('#access_token=abc123&refresh_token=r1&type=invite');
  assert.deepEqual(result, { kind: 'token', accessToken: 'abc123', type: 'invite' });
});

test('parseAuthFragment reads a recovery token', () => {
  const result = parseAuthFragment('#access_token=abc123&type=recovery');
  assert.equal(result.kind, 'token');
  assert.equal(result.type, 'recovery');
});

test('parseAuthFragment tolerates a missing leading hash', () => {
  const result = parseAuthFragment('access_token=abc123&type=invite');
  assert.equal(result.kind, 'token');
  assert.equal(result.accessToken, 'abc123');
});

test('parseAuthFragment reports an expired link', () => {
  const result = parseAuthFragment(
    '#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired',
  );
  assert.equal(result.kind, 'error');
  assert.equal(result.code, 'otp_expired');
  assert.equal(result.description, 'Email link is invalid or has expired');
});

test('parseAuthFragment reports an empty fragment as missing', () => {
  assert.deepEqual(parseAuthFragment(''), { kind: 'missing' });
  assert.deepEqual(parseAuthFragment('#'), { kind: 'missing' });
  assert.deepEqual(parseAuthFragment(undefined), { kind: 'missing' });
});

test('parseAuthFragment treats a fragment with no access_token as missing', () => {
  assert.deepEqual(parseAuthFragment('#type=invite'), { kind: 'missing' });
});

test('validatePassword accepts a valid matching password', () => {
  assert.equal(validatePassword('secret123', 'secret123'), null);
});

test('validatePassword rejects fewer than 6 characters', () => {
  assert.equal(validatePassword('abc12', 'abc12'), 'At least 6 characters');
});

test('validatePassword rejects a mismatch', () => {
  assert.equal(validatePassword('secret123', 'secret124'), 'Passwords do not match');
});

test('validatePassword rejects an empty password', () => {
  assert.equal(validatePassword('', ''), 'At least 6 characters');
});

// --- parseAuthParams: the token_hash flow -----------------------------------
// The email link now points at this page with ?token_hash=... instead of at
// GoTrue's /auth/v1/verify. Fetching this page consumes nothing, so an email
// scanner prefetching the link can no longer burn a single-use token.

test('parseAuthParams reads a recovery token_hash from the query string', () => {
  const r = parseAuthParams('?token_hash=abc123&type=recovery', '');
  assert.deepEqual(r, { kind: 'token_hash', tokenHash: 'abc123', type: 'recovery' });
});

test('parseAuthParams reads an invite token_hash', () => {
  const r = parseAuthParams('?token_hash=xyz789&type=invite', '');
  assert.equal(r.kind, 'token_hash');
  assert.equal(r.type, 'invite');
});

test('parseAuthParams reports an error given in the query string', () => {
  const r = parseAuthParams('?error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired', '');
  assert.equal(r.kind, 'error');
  assert.equal(r.code, 'otp_expired');
  assert.equal(r.description, 'Email link is invalid or has expired');
});

test('parseAuthParams reports an error given in the fragment', () => {
  const r = parseAuthParams('', '#error=access_denied&error_code=otp_expired');
  assert.equal(r.kind, 'error');
  assert.equal(r.code, 'otp_expired');
});

test('parseAuthParams still accepts a legacy fragment session', () => {
  // Links already sitting in inboxes were built the old way; keep honouring
  // them rather than stranding anyone mid-migration.
  const r = parseAuthParams('', '#access_token=tok&type=recovery');
  assert.deepEqual(r, { kind: 'session', accessToken: 'tok', type: 'recovery' });
});

test('parseAuthParams prefers an error over a token_hash', () => {
  const r = parseAuthParams('?token_hash=abc&error_code=otp_expired', '');
  assert.equal(r.kind, 'error');
});

test('parseAuthParams reports missing when there is nothing to act on', () => {
  assert.deepEqual(parseAuthParams('', ''), { kind: 'missing' });
  assert.deepEqual(parseAuthParams('?', '#'), { kind: 'missing' });
  assert.deepEqual(parseAuthParams(undefined, undefined), { kind: 'missing' });
});

test('parseAuthParams treats a token_hash with no type as missing type, not missing token', () => {
  const r = parseAuthParams('?token_hash=abc', '');
  assert.equal(r.kind, 'token_hash');
  assert.equal(r.type, '');
});

// --- createSessionProvider --------------------------------------------------
// The token_hash is single-use, but a submit can fail AFTER it is spent -- most
// commonly because Supabase rejects the new password (e.g. same as the old
// one). Re-verifying on retry would hit otp_expired and strand the user, so the
// session obtained by the first successful verify is cached and reused.

test('createSessionProvider verifies once and reuses the session on retry', async () => {
  let calls = 0;
  const provider = createSessionProvider({ verify: async () => { calls += 1; return 'session-abc'; } });

  assert.equal(await provider(), 'session-abc');
  assert.equal(await provider(), 'session-abc');
  assert.equal(await provider(), 'session-abc');
  assert.equal(calls, 1, 'verify must run only once across retries');
});

test('createSessionProvider uses a pre-existing session without verifying', async () => {
  // Legacy fragment links arrive with a session already in hand.
  let calls = 0;
  const provider = createSessionProvider({
    accessToken: 'from-fragment',
    verify: async () => { calls += 1; return 'should-not-happen'; },
  });

  assert.equal(await provider(), 'from-fragment');
  assert.equal(calls, 0);
});

test('createSessionProvider does not cache a failed verification', async () => {
  // A transient failure (network blip) must not poison later attempts.
  let calls = 0;
  const provider = createSessionProvider({
    verify: async () => {
      calls += 1;
      if (calls === 1) throw new Error('network blip');
      return 'session-xyz';
    },
  });

  await assert.rejects(() => provider(), /network blip/);
  assert.equal(await provider(), 'session-xyz');
  assert.equal(calls, 2);
});
