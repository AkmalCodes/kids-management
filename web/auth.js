// Pure helpers for the set-password page: no DOM, no network, no globals --
// everything here is directly unit-testable under `node --test`.

// GoTrue returns its result in the URL *fragment*, never the query string.
// That matters for security: browsers never transmit a fragment in an HTTP
// request, so the access token is never sent anywhere except in the explicit
// Authorization header we build ourselves.
//
// Three shapes matter:
//   #access_token=...&type=invite                   -> ready to set a password
//   #error=access_denied&error_code=otp_expired&...  -> link expired or used
//   (empty)                                          -> opened directly
export function parseAuthFragment(hash) {
  const raw = String(hash ?? '').replace(/^#/, '');
  const params = new URLSearchParams(raw);

  // Checked before access_token: GoTrue reports a dead link by redirecting
  // here with error params rather than by failing the request, so without
  // this branch an expired invite would render an empty form that only fails
  // on submit.
  const errorCode = params.get('error_code') || params.get('error');
  if (errorCode) {
    return {
      kind: 'error',
      code: errorCode,
      description: params.get('error_description') || '',
    };
  }

  const accessToken = params.get('access_token');
  if (!accessToken) return { kind: 'missing' };

  return {
    kind: 'token',
    accessToken,
    // 'invite' vs 'recovery' decides whether must_set_password gets cleared.
    type: params.get('type') || '',
  };
}

// Mirrors lib/features/auth/set_password_screen.dart:75,85 exactly. Keep the
// two in sync -- the rules are deliberately trivial so this duplication stays
// cheap, and the alternative (shipping a Flutter Web bundle to reuse the Dart
// validator) was rejected in the spec.
export function validatePassword(password, confirmation) {
  if (!password || password.length < 6) return 'At least 6 characters';
  if (password !== confirmation) return 'Passwords do not match';
  return null;
}
