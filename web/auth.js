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

// Preferred parser. Handles the token_hash flow, the legacy fragment flow, and
// errors arriving in either place.
//
// WHY token_hash IN THE QUERY STRING, when the fragment was the safer carrier:
// the email used to link straight at GoTrue's /auth/v1/verify, which is a GET
// that CONSUMES the single-use token. Mail providers and security scanners
// prefetch links, so the token was routinely spent before the recipient
// clicked -- the user saw "link has expired" on a link they had never used.
//
// Now the email links here instead. Fetching this page consumes nothing, so a
// prefetch is harmless; main.js exchanges the token only when the form is
// actually submitted. The token_hash is single-use and short-lived, and is
// exchanged over HTTPS in a POST body, so carrying it in the query string is
// an acceptable trade for a link that survives being scanned.
//
// Shapes, in precedence order:
//   ?error=... / #error=...                  -> dead link, tell the user
//   ?token_hash=...&type=recovery|invite      -> exchange on submit
//   #access_token=...&type=...                -> legacy link already in an inbox
//   nothing                                   -> opened directly
export function parseAuthParams(search, hash) {
  const query = new URLSearchParams(String(search ?? '').replace(/^\?/, ''));
  const frag = new URLSearchParams(String(hash ?? '').replace(/^#/, ''));

  // Checked first, and across both carriers: GoTrue signals a dead link by
  // redirecting with error params rather than failing the request, and which
  // carrier it uses varies by flow.
  const errorCode =
    query.get('error_code') || query.get('error') ||
    frag.get('error_code') || frag.get('error');
  if (errorCode) {
    return {
      kind: 'error',
      code: errorCode,
      description: query.get('error_description') || frag.get('error_description') || '',
    };
  }

  const tokenHash = query.get('token_hash');
  if (tokenHash) {
    return { kind: 'token_hash', tokenHash, type: query.get('type') || '' };
  }

  // Legacy: links minted before the token_hash migration redirect here with a
  // ready-made session in the fragment. Kept so in-flight emails still work.
  const accessToken = frag.get('access_token');
  if (accessToken) {
    return { kind: 'session', accessToken, type: frag.get('type') || '' };
  }

  return { kind: 'missing' };
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
