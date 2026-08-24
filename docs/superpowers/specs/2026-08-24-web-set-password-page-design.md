# Web set-password page — design

**Date:** 2026-08-24
**Status:** approved, not yet implemented
**Page URL:** `https://kids.akmalcodes.quest/`

## Problem

Invite and password-recovery emails currently point at the custom URL scheme
`com.example.kidsmanagement://login-callback/`. A custom scheme only resolves
on a device that has the app installed. There is no fallback: opened in a
desktop browser, or on a phone without the app, the link simply dead-ends.

You cannot know before the click which case you are in, so the email link
itself must point somewhere that always works. That means an `https` page.

This also affects **H1** in the main design spec: a custom scheme is
unverified, so any app can register it and intercept an invite token. Once
invites stop using the scheme, that attack surface disappears.

## Goals

- An invite or recovery link works from any browser, on any device.
- The recipient can set their password without having the app installed.
- Stop using the custom scheme for auth callbacks, retiring H1.

## Non-goals (deliberately deferred)

- **Android App Links / iOS Universal Links.** The verified-https upgrade that
  would let the OS open the app directly from the same URL. Requires a release
  keystore and `assetlinks.json`; the keystore does not exist yet (still open
  in the main design spec). Choosing the https page now is a prerequisite for
  this later, not a detour from it.
- **A Flutter Web build.** Reusing `SetPasswordScreen` would keep the password
  rules in one place, but ships a multi-MB bundle on a link click and exposes
  the whole app as an untested web surface.
- **An app-download link on the success screen.** The app is not on Play yet.
- **Any web sign-in.** The page handles exactly two token types and nothing
  else. It is not a web version of the app.

## Flow

1. A director invites someone. `create-user` calls `generateLink`, then builds
   the action link with `redirect_to=https://kids.akmalcodes.quest/`.
2. Mailgun sends that link (see `docs/mailgun-porkbun-domain-setup.md`).
3. The recipient clicks. GoTrue verifies the one-time token and issues a 302
   to `https://kids.akmalcodes.quest/#access_token=…&refresh_token=…&type=invite`.
4. The page reads `location.hash`, then immediately calls
   `history.replaceState` to strip it from the address bar.
5. The page shows the password form.
6. On submit: `PUT https://rpefksoutqsbreiyppee.supabase.co/auth/v1/user`
   with headers `apikey: <anon key>` and `Authorization: Bearer <access_token>`,
   body `{"password": "…"}`. The anon key is the same publishable key already
   passed to the app as `--dart-define=SUPABASE_ANON_KEY` in
   `.vscode/launch.json`, also readable from the Supabase dashboard.
7. **If `type=invite`**, then also
   `POST https://rpefksoutqsbreiyppee.supabase.co/rest/v1/rpc/complete_password_setup`
   with the same two headers. See below — this step is mandatory.
8. Success screen: "Password set — open Kids Management and sign in."

The recipient signs into the app with email + the password they just chose.
There is no handoff from browser to app; one uniform flow on every device.

## Why step 7 is mandatory

`complete_password_setup()` is the `SECURITY DEFINER` function that sets
`must_set_password = false` for `auth.uid()`. `AuthGate` routes on that flag
(`lib/core/auth/auth_gate.dart:39`).

If the page sets the password but skips the RPC, the invited user signs into
the app and is routed straight back to `SetPasswordScreen` — their password is
already set, but the flag still says otherwise. The page must clear the flag
itself, exactly as the app does after its own set-password step.

Skipped for `type=recovery`: an existing user resetting their password never
had `must_set_password` set. Calling it would be harmless (idempotent), but
gating on type keeps the intent explicit.

## Page states

| State | Trigger | Shows |
| --- | --- | --- |
| Parsing | initial load | brief loader |
| Form | fragment has `access_token` | password + confirm fields |
| Submitting | form submitted | disabled form, loader |
| Success | both API calls succeeded | "open the app and sign in" |
| Error — expired | fragment has `error=` | "This link has expired. Ask your director for a new invite." |
| Error — no token | fragment has neither | "This link is invalid or has already been used." |

The expired case is real and observed: GoTrue redirects with
`#error=access_denied&error_code=otp_expired&error_description=…` rather than
failing the request. Verified by `curl` against `/auth/v1/verify` with a bogus
token. Without handling it the page would render an empty form that fails on
submit with no explanation.

Validation mirrors `set_password_screen.dart:75,85` exactly: at least 6
characters, and confirmation must match. Keep the two in sync; the rules are
deliberately trivial so duplication stays cheap.

## Security

- Tokens arrive in the URL **fragment**. Browsers never transmit a fragment in
  an HTTP request, so the token is never sent anywhere except in the explicit
  `Authorization` headers above. This is why the fragment, not a query
  parameter, is the right carrier.
- `history.replaceState` clears the fragment immediately after parsing, so
  tokens do not linger in the address bar, browser history, or a shared screen.
- The embedded anon key is public by design — it already ships inside the APK
  and grants nothing on its own; RLS is what enforces access.
- The page is static. It has no backend of its own, stores nothing, and sets no
  cookies.
- After this lands, remove the `intent-filter` from `AndroidManifest.xml` and
  `CFBundleURLTypes` from `ios/Runner/Info.plist`. That retires **H1** by
  deletion rather than by verification.

## Changes outside the page

| Where | Change |
| --- | --- |
| `supabase/functions/create-user/index.ts` | `redirect_to` → `https://kids.akmalcodes.quest/` |
| — | **Redeploy the function.** A stale deployment already caused one bug. |
| `lib/core/auth/auth_controller.dart` | `sendPasswordReset` `redirectTo` → same URL |
| Supabase → Auth → URL Configuration | add `https://kids.akmalcodes.quest/` (exact — the redirect target is the root URL, so no wildcard is needed and a wildcard would only widen what an attacker could redirect to); remove `com.example.kidsmanagement://login-callback/` |
| Supabase → Auth → Site URL | `http://localhost:3000` → `https://kids.akmalcodes.quest/` |
| `android/.../AndroidManifest.xml`, `ios/Runner/Info.plist` | remove the now-dead scheme registration |
| `lib/features/auth/forgot_password_screen.dart` | update the stale scheme comment |
| `CLAUDE.md`, main design spec | record the new architecture; H1 resolved |

The `CLAUDE.md` "Auth deep-link scheme" section stays useful history — the
underscore rule still explains why the scheme approach was abandoned — but
must be rewritten to say the scheme is no longer used for auth callbacks.

## Hosting — Cloudflare Pages

Static files live in a `web/` directory in this repo and deploy to **Cloudflare
Pages**, served at `kids.akmalcodes.quest`.

**Why this provider.** The requirement was a host that attaches a custom domain
using only a CNAME record at Porkbun, with no nameserver migration. A
nameserver move would drag the entire `akmalcodes.quest` zone out of Porkbun,
including the SPF, DKIM, and tracking records that make Mailgun work — an
unacceptable risk to a flow that was only just repaired.

- **Cloudflare Pages** — meets it. Cloudflare's docs are explicit that for a
  *subdomain* you do not need to move nameservers; you create a CNAME at your
  existing provider. (Apex domains *do* require the nameserver move — which is
  another reason the page lives on `kids.` rather than the bare domain.)
- **GitHub Pages** — rejected. On the free plan Pages only publishes from a
  **public** repository; serving from a private repo needs GitHub Pro. This
  repo should not become public.

Note that Porkbun's DNS is Cloudflare-powered under the hood, but the zone is
not in *your* Cloudflare account — so Pages treats it as external DNS, which is
precisely the CNAME case above.

### Setup order (the ordering matters)

1. Create a free Cloudflare account.
2. Cloudflare dashboard → **Workers & Pages** → create a Pages project and
   deploy the `web/` directory. Note the assigned `<project>.pages.dev` address.
3. In that Pages project → **Custom domains** → add `kids.akmalcodes.quest`.
4. **Only then**, in Porkbun's DNS panel for `akmalcodes.quest`, add:
   **CNAME**, host `kids`, value `<project>.pages.dev`, TTL default (600).
5. Wait for Cloudflare to issue the TLS certificate, then load
   `https://kids.akmalcodes.quest/` and confirm it serves over https.

Step 3 must happen before step 4. Adding the CNAME without first registering
the custom domain in the Pages dashboard produces a **522 error**, because the
record points at Cloudflare with nothing on the other side claiming it.

Per the standing rule in `CLAUDE.md`, this setup gets its own step-by-step,
explain-as-you-go document in `docs/`, in the same style as
`docs/mailgun-porkbun-domain-setup.md` — not just a terse diff.

## Testing

**Automated (Dart):** update any test asserting the old `redirectTo`, and add
one asserting `sendPasswordReset` sends the https URL. The full suite
(207 tests at time of writing) must stay green.

**Pre-wiring check:** before pointing real emails at it, `curl` the verify
endpoint with a bogus token and the new `redirect_to`, and confirm the
`Location` header is the https URL rather than a Site-URL fallback. This is the
check that would have caught the underscore bug immediately.

**Manual matrix on the page:**

| Case | Expected |
| --- | --- |
| Fresh invite link | form → success → can sign into app without being re-prompted |
| Same link clicked twice | error — invalid or already used |
| Expired link | error — ask director for a new invite |
| Recovery link | form → success; `must_set_password` untouched |
| Passwords do not match | inline validation, no request sent |
| Password under 6 chars | inline validation, no request sent |
| Page opened with no fragment | error — invalid link |

The first row is the one that catches a missing step 7.

## Open questions

None. The hosting provider was the one open item and is now settled on
Cloudflare Pages, with the CNAME-only requirement confirmed against current
Cloudflare documentation.
