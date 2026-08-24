import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseAuthFragment, validatePassword } from '../auth.js';

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
