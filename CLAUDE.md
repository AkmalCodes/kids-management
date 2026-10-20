# CLAUDE.md

Instructions for Claude Code when working in this repo (**KawanKecil** —
Malay for "little friend"; formerly Kids Management / Childcare Manager /
`test_flutter`, a Flutter childcare-management app backed by Supabase). The
folder on disk is still `kids_management`. That's only the folder name, so
there's no need to rename it.

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

## Auth callbacks go to a web page, not a deep link

Invite and password-recovery emails point at `https://kids.akmalcodes.quest/`
(see `docs/superpowers/specs/2026-08-24-web-set-password-page-design.md` and
`docs/cloudflare-pages-setup.md`). The page sets the password in the browser and
clears `must_set_password` itself.

**There is no custom URL scheme registered any more.** It was removed from
`AndroidManifest.xml`, `ios/Runner/Info.plist`, and the Supabase redirect
allow-list. Do not reintroduce one without reading the history below.

**Why it was abandoned.** The scheme was `com.example.kids_management://`, and
it never worked — not before the rename either. RFC 3986 allows only letters,
digits, `+`, `-` and `.` in a URI scheme. Supabase Auth (GoTrue, Go) parses
`redirect_to` with Go's `net/url`, which finds no scheme at all in a string
containing `_`; validation then fails and GoTrue **silently** falls back to the
Site URL. No error is raised anywhere. That cost two debugging sessions and was
once misdiagnosed as a Supabase SDK bug.

Renaming it underscore-free would not have been enough: a custom scheme has no
fallback, so it dead-ends on every desktop click and on any phone without the
app installed. That is why an https page replaced it outright. Removing the
scheme also retired security finding **H1** — an unverified scheme can be
registered by any app, which made invite tokens interceptable.

If auth emails are ever repointed again, remember the deployed Edge Function is
a separate artifact: after editing `create-user`, redeploy it
(`npx supabase functions deploy create-user --project-ref rpefksoutqsbreiyppee
--use-api`) or the old value keeps being sent.

## Project identity

- Display name: `KawanKecil` (one word, two capital K's). Dart package name:
  `kawankecil`. Android applicationId / namespace and iOS bundle id:
  `com.akmalcodes.kawankecil`. Keep them in sync if any changes again. The
  rename commit "rename app to KawanKecil" lists every file that references
  them: pubspec + test imports, Android Gradle + manifest label + Kotlin
  `MainActivity` package path, iOS pbxproj + Info.plist, in-app titles, the
  web page, email templates, and `supabase/config.toml` project_id.
  Deliberately not renamed: the Cloudflare Pages project `kids-management` and
  the `kids.akmalcodes.quest` address. They're invisible to users, and renaming
  them means DNS + Supabase redirect allow-list + email link changes.
- **All auth email leaves by one door:** Supabase's mailer, configured with
  Mailgun SMTP (Auth → Emails → SMTP Settings; sender name `KawanKecil`, address
  `no-reply@mg.akmalcodes.quest`. Before the rename the name was
  `Childcare Manager`; the dashboard value is changed by hand). Bodies are the dashboard
  templates, mirrored in `docs/email-templates/` since dashboard config is
  invisible to git. `create-user` used to send invites itself via Mailgun's
  HTTP API — that was a workaround for the built-in shared relay mangling HTML,
  and was removed once SMTP made it unnecessary.
- **Email links point at the web page, never at `/auth/v1/verify`.** That
  endpoint is a GET which consumes the single-use token, and mail scanners
  prefetch links, so recipients got "link has expired" on links they had never
  clicked. Templates build `https://kids.akmalcodes.quest/?token_hash={{ .TokenHash }}&type=…`
  instead; the page exchanges the token only on form submit.
