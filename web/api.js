// The two Supabase REST calls this page makes. `fetchImpl` is injectable so
// these are unit-testable without a network or a browser.

// Sets the signed-in user's password. PUT /auth/v1/user is GoTrue's own
// "update the current user" endpoint; the Bearer token from the email link is
// what identifies who that user is, so no old password is needed -- possession
// of the one-time link is the proof of identity.
export async function setPassword({ supabaseUrl, anonKey, accessToken, password, fetchImpl = fetch }) {
  const response = await fetchImpl(`${supabaseUrl}/auth/v1/user`, {
    method: 'PUT',
    headers: {
      'Content-Type': 'application/json',
      apikey: anonKey,
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({ password }),
  });
  if (!response.ok) throw new Error(await readError(response));
}

// Clears profiles.must_set_password for the invited user.
//
// This is NOT optional and its absence fails invisibly. AuthGate
// (lib/core/auth/auth_gate.dart:39) routes on that flag, so an invited user
// whose password is set but whose flag is still true signs into the app and is
// sent straight back to SetPasswordScreen -- forever.
//
// complete_password_setup() is SECURITY DEFINER and takes no arguments; it
// acts on auth.uid(), which the Bearer token establishes. It exists so users
// never need a broad UPDATE policy on their own profile row (which would let
// them change their own role).
export async function completePasswordSetup({ supabaseUrl, anonKey, accessToken, fetchImpl = fetch }) {
  const response = await fetchImpl(`${supabaseUrl}/rest/v1/rpc/complete_password_setup`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: anonKey,
      Authorization: `Bearer ${accessToken}`,
    },
    body: '{}',
  });
  if (!response.ok) throw new Error(await readError(response));
}

// Supabase spreads its error text across a few different keys depending on
// which service answered, so try each before falling back to the status.
async function readError(response) {
  try {
    const body = await response.json();
    return body.msg || body.message || body.error_description || `Request failed (${response.status})`;
  } catch {
    return `Request failed (${response.status})`;
  }
}
