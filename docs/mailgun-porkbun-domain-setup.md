# Setting up a custom Mailgun sending domain (Porkbun DNS)

This is a beginner-friendly walkthrough of how we moved off Mailgun's sandbox
domain onto a real domain (`akmalcodes.quest`, bought on Porkbun) for sending
invite / password-reset emails. Read this before touching anything
email-related in this project.

## Why this was needed

Mailgun gives every new account a free "sandbox" domain
(`sandboxXXXXXXXX.mailgun.org`). It works, but only sends email to addresses
you've manually "authorized" in the Mailgun dashboard — fine for testing,
useless for real users. A verified custom domain removes that limit.

## Concepts (skip if you already know these)

- **DNS record**: a line in your domain's public "phone book" that tells the
  internet where to find things for your domain (which mail server handles
  it, which server hosts your website, etc).
- **SPF (TXT record)**: a list of servers allowed to send email *as* your
  domain. Without it, receiving mail servers are more likely to mark your
  email as spam.
- **DKIM (TXT record)**: a cryptographic signature added to every email so
  the receiving server can verify it wasn't tampered with and really came
  from you.
- **CNAME (tracking record)**: lets Mailgun rewrite links in your emails so
  it can report opens/clicks back to you. Not required for delivery, just
  analytics.
- **MX record**: tells the internet which server handles *incoming* mail for
  a domain. We do **not** need this — the app only sends mail, it never
  receives any, so we skip MX records on purpose.
- **Subdomain vs root domain**: we used `mg.akmalcodes.quest` (a subdomain)
  instead of the bare `akmalcodes.quest`. This keeps sending-related DNS
  records isolated from anything else that might later live on the root
  domain (a website, other services, etc).

## Step-by-step

1. **Log into Mailgun** ([app.mailgun.com](https://app.mailgun.com)) with the
   account tied to this project.
2. Go to **Sending → Domains → Add new domain**.
3. Enter the domain name. We used `mg.akmalcodes.quest` (subdomain
   recommended — see above). Leave region as **US**, IP assignment as
   **Shared IP**, DKIM key length **1024** (defaults are fine). Skip the
   Red Sift / DMARC checkbox — that's a separate third-party opt-in, not
   required.
4. Click **Add Domain**. Mailgun generates the DNS records you need under
   the **DNS Records** tab:
   - Sending records: 1 TXT (SPF), 1 TXT (DKIM)
   - Receiving records: 2 MX — **skip these**, we don't receive mail
   - Tracking records: 1 CNAME
5. **Log into Porkbun** ([porkbun.com](https://porkbun.com/account)), find
   the domain, click the **DNS** icon on its row to open the DNS panel
   (Porkbun's DNS is Cloudflare-powered under the hood).
6. Click **+ Add record** for each of the 3 records Mailgun gave you:
   - **TXT**, host = `mg` (just the subdomain part — Porkbun appends
     `.akmalcodes.quest` automatically), value = the `v=spf1 ...` string.
   - **TXT**, host = `krs._domainkey.mg`, value = the long `k=rsa; p=...`
     DKIM string (copy it exactly, it's long).
   - **CNAME**, host = `email.mg`, value = `mailgun.org`.
   - Leave TTL at the default (600).
7. Back in Mailgun, click **Check status** on the DNS Records tab. DNS
   propagation can take anywhere from a few minutes to a few hours, but
   Porkbun/Cloudflare is usually fast (verified within seconds for us).
   You want to see **Verified** (SPF, CNAME) and **Active** (DKIM) — MX
   stays **Unverified**, which is expected since we skipped it.
8. **Update the app's config**: the domain is only *used* once the
   `MAILGUN_DOMAIN` secret (used by the `create-user` Supabase Edge
   Function) is switched from the sandbox domain to the new verified
   domain, and the function is redeployed. See
   `supabase/functions/create-user/index.ts` for where it's read.
9. **Test it**: trigger an invite or password-reset email from the app and
   confirm it actually lands in an inbox (not just "accepted" in Mailgun's
   logs).

## Record of what we set up for this project

| Type  | Host                          | Value                                                    |
|-------|-------------------------------|-----------------------------------------------------------|
| TXT   | `mg.akmalcodes.quest`         | `v=spf1 include:mailgun.org ~all`                          |
| TXT   | `krs._domainkey.mg.akmalcodes.quest` | `k=rsa; p=<DKIM public key — see Mailgun dashboard>` |
| CNAME | `email.mg.akmalcodes.quest`   | `mailgun.org`                                              |

Sending domain: `mg.akmalcodes.quest`
Deep-link scheme (unrelated to Mailgun, just noting it uses the same brand):
`com.example.kidsmanagement://login-callback/` — **no underscore**, see the
"Auth deep-link scheme" section in `CLAUDE.md` for why.

## Gotchas we hit

- Mailgun account needs to be **activated** (check the email it sends on
  signup) before it will actually deliver mail, even with a verified
  domain — a green "Verified" badge doesn't guarantee sending works.
- Don't add the MX records unless you actually want this domain to
  *receive* email through Mailgun. Adding them is harmless but unnecessary
  for a sending-only app.
