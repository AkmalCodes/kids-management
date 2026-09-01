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

## Flow (revised 2026-09-01 — token_hash)

**Superseded design:** the email originally linked at GoTrue's
`/auth/v1/verify`, which redirected here with a session in the URL fragment.
That is a `GET` which **consumes the single-use token**, and mail providers and
security scanners prefetch links — so tokens were spent before the recipient
clicked, and they saw "this link has expired" for a link they had never used.
Observed in production on recovery; invites used the same shape and were
vulnerable to the same failure.

The email now links at this page carrying `?token_hash=…&type=…`. Fetching a
static page consumes nothing, so a prefetch is inert. The page exchanges the
token by `POST /auth/v1/verify` with `{type, token_hash}` **only on form
submit**, so a deliberate human action is the only thing that can spend it.
Invite and recovery now share this one mechanism. The legacy fragment shape is
still accepted so links already in inboxes keep working.

1. A director invites someone. `create-user` calls `generateLink`, then builds
   the link by hand from `properties.hashed_token`:
   `https://kids.akmalcodes.quest/?token_hash=<hash>&type=invite`.
   Recovery emails are built the same way by the Supabase template
   (`docs/email-templates/reset-password.html`) from `{{ .TokenHash }}`.
2. Mailgun sends that link (see `docs/mailgun-porkbun-domain-setup.md`).
3. The recipient clicks — or a scanner prefetches it, harmlessly. The page is
   static; loading it consumes nothing.
4. The page reads `token_hash` and `type` from the query string, then calls
   `history.replaceState` to strip them from the address bar.
5. The page shows the password form. **No network call has happened yet.**
6. On submit, and only on submit:
   a. `POST /auth/v1/verify` with `{type, token_hash}` and the `apikey` header
      — no `Authorization`, since there is no session yet. This is the call
      that consumes the token; it returns `access_token`.
   b. `PUT /auth/v1/user` with `apikey` + `Authorization: Bearer <access_token>`
      and body `{"password": "…"}`. The anon key is the same publishable key
      passed to the app as `--dart-define=SUPABASE_ANON_KEY` in
      `.vscode/launch.json`.
7. **If `type=invite`**, then also
   `POST /rest/v1/rpc/complete_password_setup` with the same two headers.
   See below — this step is mandatory.
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
| Form | query has `token_hash` (or legacy fragment `access_token`) | password + confirm fields |
| Submitting | form submitted | disabled form, loader |
| Success | verify + set-password (+ RPC) all succeeded | "open the app and sign in" |
| Error — expired | `error=` in query **or** fragment | "This link has expired. Ask your director for a new invite." |
| Error — no token | neither carrier has anything | "This link is invalid or has already been used." |

The expired case is real and observed: GoTrue signals a dead link by redirecting
with `error=access_denied&error_code=otp_expired&…` rather than failing the
request, and it uses the query string, the fragment, or both depending on the
flow — so the parser checks both. A spent `token_hash` instead surfaces at
submit time, as the error message returned by `POST /auth/v1/verify`.

Validation mirrors `set_password_screen.dart:75,85` exactly: at least 6
characters, and confirmation must match. Keep the two in sync; the rules are
deliberately trivial so duplication stays cheap.

## Security

- The `token_hash` arrives as a **query parameter**, which is a deliberate
  trade. A fragment is the more private carrier — browsers never transmit it —
  but a fragment cannot be obtained without a link that consumes the token on
  `GET`, which is the prefetch problem described above. The `token_hash` is
  single-use, short-lived, and exchanged in a `POST` body over HTTPS.
- `history.replaceState` strips `token_hash`, `type`, and any error parameters
  from **both** the query string and the fragment immediately after parsing,
  so nothing lingers in the address bar, browser history, or a shared screen.
  Unrelated query parameters are preserved. This matters more than it did with
  a fragment: a query string is re-sent to the server on later navigations.
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
