# Hosting the set-password page (Cloudflare Pages + Porkbun DNS)

A beginner-friendly walkthrough of how `https://kids.akmalcodes.quest/` was set
up. Read this before touching anything to do with that page, its hosting, or
the `kids` DNS record.

Companion to `docs/mailgun-porkbun-domain-setup.md`, which covers the email
side of the same domain. **Both use `akmalcodes.quest`, so a mistake in one can
break the other** — that risk is the main thing this document exists to explain.

## Why this page exists

Invite and password-reset emails used to link to `com.example.kidsmanagement://`,
a *custom URL scheme*. A custom scheme only works on a device that has the app
installed. Click it on a laptop, or on a phone before installing the app, and it
dead-ends — there is no fallback, and you cannot tell before the click which
case you are in.

So the email now links to a normal `https://` page instead. That page sets the
password directly in the browser and works everywhere. See
`docs/superpowers/specs/2026-08-24-web-set-password-page-design.md`.

## Concepts (skip if you know these)

- **Static hosting**: the page is just HTML, CSS, and JavaScript files. No
  server-side code, no database. A static host takes those files and serves
  them. There is nothing to keep running and nothing to patch.
- **Cloudflare Pages**: Cloudflare's static hosting product. Free tier is
  plenty here.
- **CNAME record**: a DNS record meaning "this name is an alias for that other
  name." Our `kids` record says *`kids.akmalcodes.quest` is really
  `kids-management.pages.dev`*.
- **Nameservers**: the authoritative source for a domain's DNS records. Ours
  are at Porkbun. Moving them elsewhere moves **every** record for the domain.
- **TLS certificate**: what makes `https://` work. Cloudflare issues one
  automatically once it can prove the domain points at it.

## The one decision that mattered

When adding the custom domain, Cloudflare offers two paths:

1. **Cloudflare DNS** — transfer the domain's DNS to Cloudflare.
2. **My DNS provider** — keep DNS where it is, add a CNAME.

**We chose option 2, deliberately.** Option 1 would move the whole
`akmalcodes.quest` zone off Porkbun, taking the Mailgun `SPF`, `DKIM`, and
tracking records with it. Those took real effort to get right, and breaking them
means invite emails silently stop being delivered. Option 2 touches exactly one
record and leaves everything else alone.

Two consequences worth remembering:

- This is also why the page lives on a **subdomain** (`kids.`) rather than the
  bare domain. Cloudflare Pages can only attach an apex domain
  (`akmalcodes.quest` with no prefix) if you *do* move the nameservers. A
  subdomain works with a plain CNAME.
- **GitHub Pages was rejected** for this: on its free plan it only publishes
  from a public repository, and this repo should stay private.

## What was actually set up

| Thing | Value |
| --- | --- |
| Cloudflare account | `Akmalhisyam97@gmail.com` |
| Pages project | `kids-management` |
| Cloudflare-provided address | `kids-management.pages.dev` |
| Custom domain | `kids.akmalcodes.quest` |
| DNS record added at Porkbun | CNAME, host `kids`, target `kids-management.pages.dev`, TTL 600 |
| Deployed from | the `web/` directory of this repo |

## Step-by-step

### 1. Authorise the CLI (once)

Deployments are done with **Wrangler**, Cloudflare's command-line tool. It needs
to be linked to the Cloudflare account one time:

```bash
npx wrangler login
```

This opens a Cloudflare page in the browser asking you to approve access. Click
**Allow**. Wrangler stores the token itself, at
`C:\Users\<you>\AppData\Roaming\xdg.config\.wrangler\config\default.toml`.

Note the consent screen asks for a **broad** set of permissions — Workers,
Pages, D1, queues, SSL certificates, and Cloudflare's own email products among
others. That is Wrangler's standard scope list, not something this project
chose. It cannot touch Mailgun, which is an entirely separate company and
account.

Check it worked:

```bash
npx wrangler whoami
```

### 2. Create the Pages project (once)

```bash
npx wrangler pages project create kids-management --production-branch=main
```

### 3. Deploy the files

**Do not deploy the `web/` folder directly.** It contains `test/` and
`package.json`, which are for Node and have no business being on a public
website. Copy just the six site files plus the `fonts/` directory to a
temporary folder and deploy that:

```bash
STAGE=/tmp/pages-dist
rm -rf "$STAGE" && mkdir -p "$STAGE"
cp web/index.html web/styles.css web/config.js web/main.js web/auth.js web/api.js "$STAGE/"
cp -r web/fonts "$STAGE/"
npx wrangler pages deploy "$STAGE" --project-name=kids-management --branch=main --commit-dirty=true
```

(An `.assetsignore` file does **not** work here — that is a Workers feature and
Cloudflare Pages ignores it. This was tried; the test files went public until
the staging-folder approach replaced it.)

### 4. Add the custom domain — before touching DNS

In the Cloudflare dashboard: **Workers & Pages → kids-management → Custom
domains → Set up a custom domain**, enter `kids.akmalcodes.quest`, then choose
**My DNS provider → Begin CNAME setup**.

Cloudflare then shows the record it expects: name `kids`, target
`kids-management.pages.dev`.

**This step must come before step 5.** If the CNAME exists while Cloudflare has
no record of the domain, visitors get a **522 error** — the record points at
Cloudflare, and Cloudflare does not know what to serve.

### 5. Add the CNAME at Porkbun

1. Log into Porkbun, find `akmalcodes.quest`, click the **DNS** icon.
2. **+ Add record**:
   - Type: **CNAME**
   - Host: `kids` (Porkbun appends `.akmalcodes.quest` automatically)
   - Answer: `kids-management.pages.dev`
   - TTL: leave the default (600)
3. **Add**.

Do not modify or delete any existing record. The `mg`, `krs._domainkey.mg`, and
`email.mg` entries are Mailgun's and must stay exactly as they are.

### 6. Verify

Back in Cloudflare's Custom domains tab, click **Check DNS records**. Status
goes from *Inactive (Requires DNS setup)* to active once the certificate is
issued — usually a couple of minutes, though Cloudflare warns it can take up to
24 hours.

Then confirm from a terminal:

```bash
# The new record resolves
nslookup -type=CNAME kids.akmalcodes.quest

# The page serves over https with a valid certificate
curl -sS -o /dev/null -w "http=%{http_code} tls=%{ssl_verify_result}\n" https://kids.akmalcodes.quest/
```

Expect `http=200 tls=0` (`tls=0` means the certificate verified).

**Always re-check Mailgun afterwards.** Any DNS change is a chance to have
broken email:

```bash
nslookup -type=TXT mg.akmalcodes.quest
nslookup -type=TXT krs._domainkey.mg.akmalcodes.quest
nslookup -type=CNAME email.mg.akmalcodes.quest
```

All three must still return values. If any disappears, invite emails will start
landing in spam or failing outright.

## Redeploying after a change

Any edit to files in `web/` needs a redeploy — the live site does not update
from git. Repeat **step 3** only; the domain and DNS stay as they are.

Check the result:

```bash
curl -s https://kids.akmalcodes.quest/ | head -5
```

Browsers cache aggressively, so use a hard reload (Ctrl+F5) when checking
visually.

## Gotchas we hit

- **`.assetsignore` does nothing on Pages.** It is a Workers-assets feature.
  Deploy from a clean staging folder instead, or test files end up public.
- **Cloudflare pushes Workers, not Pages, for new projects.** Take the
  "Looking to deploy Pages? Get started" path. Workers custom domains
  *require* the zone to be on Cloudflare, which would force the nameserver
  move this setup exists to avoid.
- **Changing only the `#fragment` in the address bar does not reload the page**,
  so the page appears not to react. Real users always arrive via a fresh page
  load from the email link, so this only affects manual testing — force a
  reload (F5) when testing the different states by hand.
- **The dashboard's drag-and-drop uploader cannot be scripted.** Wrangler is
  the reliable path, and gives a repeatable one-line redeploy.
