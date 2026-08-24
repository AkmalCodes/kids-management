# CLAUDE.md

Instructions for Claude Code when working in this repo (Kids Management —
formerly `test_flutter`, a Flutter childcare-management app backed by
Supabase).

## Docs to read before making changes

- `docs/superpowers/specs/2026-07-01-childcare-management-design.md` — full
  design spec (auth/RBAC, navigation, data model).
- `docs/mailgun-porkbun-domain-setup.md` — how the Mailgun sending domain
  (`mg.akmalcodes.quest`, DNS on Porkbun) is set up. **Read this before
  touching anything related to: outbound email, `MAILGUN_DOMAIN` /
  `MAILGUN_API_KEY`, the deep-link scheme
  (`com.example.kidsmanagement://login-callback/`), or DNS records on
  `akmalcodes.quest`.** The user is a newbie with Mailgun/DNS — any change
  in this area needs the same step-by-step, explain-as-you-go treatment as
  that doc, not just a terse diff.

## Auth deep-link scheme — do not add an underscore

The scheme is `com.example.kidsmanagement` (no underscore), which
deliberately does **not** match the applicationId
`com.example.kids_management`. RFC 3986 allows only letters, digits, `+`,
`-` and `.` in a URI scheme. Supabase Auth (GoTrue, Go) parses
`redirect_to` with Go's `net/url`; an underscore makes that parser find no
scheme at all, redirect-URL validation fails, and GoTrue **silently** falls
back to the project's Site URL (`http://localhost:3000`) instead of opening
the app — no error anywhere. This cost two debugging sessions and was
misdiagnosed once as a Supabase SDK bug.

The scheme is duplicated in `AndroidManifest.xml`, `ios/Runner/Info.plist`,
`lib/core/auth/auth_controller.dart`, `supabase/functions/create-user/index.ts`,
and the Supabase dashboard's **Auth → URL Configuration → Redirect URLs**
allow-list. All five must move together. After editing the Edge Function you
must redeploy it (`npx supabase functions deploy create-user --project-ref
rpefksoutqsbreiyppee --use-api`) — the deployed copy went stale through the
`test_flutter` rename and kept emitting the old scheme.

Custom-scheme links only resolve on a device/emulator with the app
installed. Clicking an invite link in a desktop browser can never open the
app — test invites on the Android device, not on Windows.

## Project identity

- Package name: `kids_management`. Android applicationId / iOS bundle id:
  `com.example.kids_management`. Keep these three in sync if either ever
  changes again — see git history around the `test_flutter` →
  `kids-management` rename for the full list of files that reference the
  package/bundle id (Android manifest + Gradle, iOS Info.plist + pbxproj,
  Kotlin `MainActivity` package path, Supabase edge function redirect URLs,
  `.iml` files).
- Supabase edge function `create-user` sends invite/reset emails directly
  via Mailgun's HTTP API (not Supabase's built-in email) — see comments in
  `supabase/functions/create-user/index.ts`.
