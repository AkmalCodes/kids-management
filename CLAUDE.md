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
  (`com.example.kids_management://login-callback/`), or DNS records on
  `akmalcodes.quest`.** The user is a newbie with Mailgun/DNS — any change
  in this area needs the same step-by-step, explain-as-you-go treatment as
  that doc, not just a terse diff.

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
