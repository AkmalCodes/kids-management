# Web Set-Password Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Serve a static page at `https://kids.akmalcodes.quest/` that lets an invited or password-recovering user set their password in any browser, so auth emails no longer dead-end when the app is absent.

**Architecture:** A dependency-free static page reads the auth token GoTrue puts in the URL fragment and makes two REST calls to Supabase — `PUT /auth/v1/user` to set the password, then `POST /rest/v1/rpc/complete_password_setup` to clear `must_set_password`. Pure logic (fragment parsing, validation) and network calls live in separate ES modules so they are unit-testable under Node's built-in test runner; only DOM wiring is untested. The invite/recovery emails are repointed from the custom URL scheme to this https page, after which the scheme registration is deleted.

**Tech Stack:** Plain HTML/CSS/ES modules (no libraries, no build step), Node `node:test` for unit tests, Cloudflare Pages for hosting, Porkbun for DNS, existing Flutter + Supabase Edge Function for the callers.

**Spec:** `docs/superpowers/specs/2026-08-24-web-set-password-page-design.md`

## Global Constraints

- Page URL is exactly `https://kids.akmalcodes.quest/` — used verbatim in the Edge Function, the Dart client, and the Supabase allow-list.
- Supabase project ref: `rpefksoutqsbreiyppee`. API base: `https://rpefksoutqsbreiyppee.supabase.co`.
- Anon key (publishable, already ships inside the APK — safe to commit): `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwZWZrc291dHFzYnJlaXlwcGVlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM2NTczNTksImV4cCI6MjA5OTIzMzM1OX0.5JaEhJGwO75hIoBOb7wM2hpPDmsr1AenTM8-tCgtIRM`
- Password rules must match `lib/features/auth/set_password_screen.dart:75,85` exactly: **at least 6 characters**, and **confirmation must match**.
- No third-party JavaScript. No build step. No bundler.
- **Ordering is load-bearing:** the page must be live (Task 4) and the allow-list updated (Task 5) *before* emails are repointed at it (Task 6). Reversing this sends real invites to a URL that does not exist.
- Never commit `.vscode/launch.json` or the service role key.
- Do not add a `Co-Authored-By` trailer to commits.

---

### Task 1: Fragment parsing and password validation

Pure functions, no DOM and no network, so they can be tested directly.

**Files:**
- Create: `web/package.json`
- Create: `web/auth.js`
- Test: `web/test/auth.test.js`

**Interfaces:**
- Consumes: nothing (first task).
- Produces:
  - `parseAuthFragment(hash: string) -> {kind: 'token', accessToken: string, type: string} | {kind: 'error', code: string, description: string} | {kind: 'missing'}`
  - `validatePassword(password: string, confirmation: string) -> string | null` (returns the error message, or `null` when valid)

- [ ] **Step 1: Create `web/package.json`**

This exists only so Node treats `.js` files in `web/` as ES modules. It is not a dependency manifest and nothing installs from it. Cloudflare Pages will not build this project — Task 4 uses direct upload, which runs no build step.

```json
{
  "name": "kids-management-web",
  "private": true,
  "type": "module"
}
```

- [ ] **Step 2: Write the failing test**

Create `web/test/auth.test.js`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseAuthFragment, validatePassword } from '../auth.js';

test('parseAuthFragment reads an invite token', () => {
  const result = parseAuthFragment('#access_token=abc123&refresh_token=r1&type=invite');
  assert.deepEqual(result, { kind: 'token', accessToken: 'abc123', type: 'invite' });
});

test('parseAuthFragment reads a recovery token', () => {
  const result = parseAuthFragment('#access_token=abc123&type=recovery');
  assert.equal(result.kind, 'token');
  assert.equal(result.type, 'recovery');
});

test('parseAuthFragment tolerates a missing leading hash', () => {
  const result = parseAuthFragment('access_token=abc123&type=invite');
  assert.equal(result.kind, 'token');
  assert.equal(result.accessToken, 'abc123');
});

test('parseAuthFragment reports an expired link', () => {
  const result = parseAuthFragment(
    '#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired',
  );
  assert.equal(result.kind, 'error');
  assert.equal(result.code, 'otp_expired');
  assert.equal(result.description, 'Email link is invalid or has expired');
});

test('parseAuthFragment reports an empty fragment as missing', () => {
  assert.deepEqual(parseAuthFragment(''), { kind: 'missing' });
  assert.deepEqual(parseAuthFragment('#'), { kind: 'missing' });
  assert.deepEqual(parseAuthFragment(undefined), { kind: 'missing' });
});

test('parseAuthFragment treats a fragment with no access_token as missing', () => {
  assert.deepEqual(parseAuthFragment('#type=invite'), { kind: 'missing' });
});

test('validatePassword accepts a valid matching password', () => {
  assert.equal(validatePassword('secret123', 'secret123'), null);
});

test('validatePassword rejects fewer than 6 characters', () => {
  assert.equal(validatePassword('abc12', 'abc12'), 'At least 6 characters');
});

test('validatePassword rejects a mismatch', () => {
  assert.equal(validatePassword('secret123', 'secret124'), 'Passwords do not match');
});

test('validatePassword rejects an empty password', () => {
  assert.equal(validatePassword('', ''), 'At least 6 characters');
});
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `node --test web/test/auth.test.js`
Expected: FAIL — `Cannot find module` / `ERR_MODULE_NOT_FOUND` for `../auth.js`.

- [ ] **Step 4: Write the implementation**

Create `web/auth.js`:

```js
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
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `node --test web/test/auth.test.js`
Expected: PASS — `# pass 10`, `# fail 0`.

- [ ] **Step 6: Commit**

```bash
git add web/package.json web/auth.js web/test/auth.test.js
git commit -m "feat(web): fragment parsing and password validation for set-password page"
```

---

### Task 2: Supabase REST calls

Both network calls, with `fetch` injected so they are testable without a network or a browser.

**Files:**
- Create: `web/api.js`
- Test: `web/test/api.test.js`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces:
  - `setPassword({supabaseUrl, anonKey, accessToken, password, fetchImpl}) -> Promise<void>` (throws `Error` with a readable message on failure)
  - `completePasswordSetup({supabaseUrl, anonKey, accessToken, fetchImpl}) -> Promise<void>` (throws `Error` on failure)

- [ ] **Step 1: Write the failing test**

Create `web/test/api.test.js`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setPassword, completePasswordSetup } from '../api.js';

const BASE = 'https://example.supabase.co';
const KEY = 'anon-key';

// Minimal stand-in for the parts of fetch's Response that api.js touches.
function fakeFetch({ ok = true, status = 200, body = {} } = {}) {
  const calls = [];
  const impl = async (url, options) => {
    calls.push({ url, options });
    return {
      ok,
      status,
      json: async () => body,
    };
  };
  impl.calls = calls;
  return impl;
}

test('setPassword PUTs to /auth/v1/user with both auth headers', async () => {
  const fetchImpl = fakeFetch();

  await setPassword({
    supabaseUrl: BASE,
    anonKey: KEY,
    accessToken: 'token-1',
    password: 'secret123',
    fetchImpl,
  });

  assert.equal(fetchImpl.calls.length, 1);
  const { url, options } = fetchImpl.calls[0];
  assert.equal(url, `${BASE}/auth/v1/user`);
  assert.equal(options.method, 'PUT');
  assert.equal(options.headers.apikey, KEY);
  assert.equal(options.headers.Authorization, 'Bearer token-1');
  assert.deepEqual(JSON.parse(options.body), { password: 'secret123' });
});

test('setPassword throws the API message on failure', async () => {
  const fetchImpl = fakeFetch({ ok: false, status: 422, body: { msg: 'Password is too short' } });

  await assert.rejects(
    () => setPassword({
      supabaseUrl: BASE,
      anonKey: KEY,
      accessToken: 'token-1',
      password: 'x',
      fetchImpl,
    }),
    /Password is too short/,
  );
});

test('setPassword falls back to a status message when the body is not JSON', async () => {
  const fetchImpl = async () => ({
    ok: false,
    status: 500,
    json: async () => { throw new Error('not json'); },
  });

  await assert.rejects(
    () => setPassword({
      supabaseUrl: BASE,
      anonKey: KEY,
      accessToken: 'token-1',
      password: 'secret123',
      fetchImpl,
    }),
    /Request failed \(500\)/,
  );
});

test('completePasswordSetup POSTs to the RPC endpoint', async () => {
  const fetchImpl = fakeFetch();

  await completePasswordSetup({
    supabaseUrl: BASE,
    anonKey: KEY,
    accessToken: 'token-2',
    fetchImpl,
  });

  assert.equal(fetchImpl.calls.length, 1);
  const { url, options } = fetchImpl.calls[0];
  assert.equal(url, `${BASE}/rest/v1/rpc/complete_password_setup`);
  assert.equal(options.method, 'POST');
  assert.equal(options.headers.apikey, KEY);
  assert.equal(options.headers.Authorization, 'Bearer token-2');
});

test('completePasswordSetup throws on failure', async () => {
  const fetchImpl = fakeFetch({ ok: false, status: 401, body: { message: 'JWT expired' } });

  await assert.rejects(
    () => completePasswordSetup({
      supabaseUrl: BASE,
      anonKey: KEY,
      accessToken: 'token-2',
      fetchImpl,
    }),
    /JWT expired/,
  );
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `node --test web/test/api.test.js`
Expected: FAIL — `ERR_MODULE_NOT_FOUND` for `../api.js`.

- [ ] **Step 3: Write the implementation**

Create `web/api.js`:

```js
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `node --test web/test/api.test.js`
Expected: PASS — `# pass 5`, `# fail 0`.

- [ ] **Step 5: Run the whole web suite**

Run: `npm test --prefix web`

(Not `node --test web/test/` — on Windows, Node treats a bare directory path
there as a single test file and reports a spurious failure. The `test` script in
`web/package.json` uses the glob form, which works everywhere.)
Expected: PASS — `# pass 15`, `# fail 0`.

- [ ] **Step 6: Commit**

```bash
git add web/api.js web/test/api.test.js
git commit -m "feat(web): Supabase REST calls for setting a password and clearing the flag"
```

---

### Task 3: Page markup, styles, and wiring

The only untested layer — DOM and browser globals. Everything with logic in it was already covered by Tasks 1 and 2.

**Files:**
- Create: `web/index.html`
- Create: `web/styles.css`
- Create: `web/config.js`
- Create: `web/main.js`

**Interfaces:**
- Consumes: `parseAuthFragment`, `validatePassword` (Task 1); `setPassword`, `completePasswordSetup` (Task 2).
- Produces: the deployable static site. Nothing imports it.

- [ ] **Step 1: Create `web/config.js`**

```js
// Both values are public by design. The anon key already ships inside the
// APK and grants nothing on its own -- RLS is what enforces access.
export const SUPABASE_URL = 'https://rpefksoutqsbreiyppee.supabase.co';
export const ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJwZWZrc291dHFzYnJlaXlwcGVlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM2NTczNTksImV4cCI6MjA5OTIzMzM1OX0.5JaEhJGwO75hIoBOb7wM2hpPDmsr1AenTM8-tCgtIRM';
```

- [ ] **Step 2: Create `web/index.html`**

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Set your password — Kids Management</title>
  <link rel="stylesheet" href="styles.css">
</head>
<body>
  <main class="card">
    <h1>Kids Management</h1>

    <!-- Exactly one of these sections is visible at a time; main.js owns the
         switching. Starts on the loader because parsing happens on load. -->
    <section id="state-loading">
      <p class="muted">Checking your link…</p>
    </section>

    <section id="state-form" hidden>
      <p id="form-intro">Choose a password for your account.</p>
      <form id="password-form" novalidate>
        <label for="password">New password</label>
        <input id="password" type="password" autocomplete="new-password" required>

        <label for="confirmation">Confirm password</label>
        <input id="confirmation" type="password" autocomplete="new-password" required>

        <p id="form-error" class="error" role="alert" hidden></p>

        <button id="submit" type="submit">Set password</button>
      </form>
    </section>

    <section id="state-success" hidden>
      <h2>Password set</h2>
      <p>Open the Kids Management app and sign in with your email and new password.</p>
    </section>

    <section id="state-error" hidden>
      <h2 id="error-title">This link doesn't work</h2>
      <p id="error-message"></p>
    </section>
  </main>

  <script type="module" src="main.js"></script>
</body>
</html>
```

- [ ] **Step 3: Create `web/styles.css`**

```css
:root {
  --bg: #f4f6f8;
  --card: #ffffff;
  --text: #1c1f23;
  --muted: #5b6470;
  --accent: #2f6fed;
  --error: #c0392b;
  --border: #d7dce3;
}

* { box-sizing: border-box; }

body {
  margin: 0;
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 24px;
  background: var(--bg);
  color: var(--text);
  font: 16px/1.5 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
}

.card {
  width: 100%;
  max-width: 380px;
  background: var(--card);
  border-radius: 12px;
  padding: 32px;
  box-shadow: 0 2px 12px rgba(0, 0, 0, 0.08);
}

h1 { font-size: 20px; margin: 0 0 20px; }
h2 { font-size: 18px; margin: 0 0 8px; }
p { margin: 0 0 16px; }
.muted { color: var(--muted); }
.error { color: var(--error); }

label {
  display: block;
  margin-bottom: 6px;
  font-size: 14px;
  color: var(--muted);
}

input {
  width: 100%;
  padding: 10px 12px;
  margin-bottom: 16px;
  border: 1px solid var(--border);
  border-radius: 8px;
  font-size: 16px;
}

input:focus {
  outline: 2px solid var(--accent);
  outline-offset: 1px;
  border-color: var(--accent);
}

button {
  width: 100%;
  padding: 12px;
  border: 0;
  border-radius: 8px;
  background: var(--accent);
  color: #fff;
  font-size: 16px;
  cursor: pointer;
}

button:disabled { opacity: 0.6; cursor: default; }

[hidden] { display: none !important; }
```

- [ ] **Step 4: Create `web/main.js`**

```js
import { SUPABASE_URL, ANON_KEY } from './config.js';
import { parseAuthFragment, validatePassword } from './auth.js';
import { setPassword, completePasswordSetup } from './api.js';

const sections = {
  loading: document.getElementById('state-loading'),
  form: document.getElementById('state-form'),
  success: document.getElementById('state-success'),
  error: document.getElementById('state-error'),
};

const form = document.getElementById('password-form');
const passwordInput = document.getElementById('password');
const confirmationInput = document.getElementById('confirmation');
const formError = document.getElementById('form-error');
const submitButton = document.getElementById('submit');
const formIntro = document.getElementById('form-intro');
const errorTitle = document.getElementById('error-title');
const errorMessage = document.getElementById('error-message');

function show(name) {
  for (const [key, node] of Object.entries(sections)) {
    node.hidden = key !== name;
  }
}

function showFormError(message) {
  formError.textContent = message;
  formError.hidden = !message;
}

function showFatal(title, message) {
  errorTitle.textContent = title;
  errorMessage.textContent = message;
  show('error');
}

const parsed = parseAuthFragment(window.location.hash);

// Strip the fragment as soon as it has been read, so the token stops showing
// in the address bar, browser history, and any shared screen. replaceState
// rewrites the current entry rather than adding one, so Back still works.
history.replaceState(null, '', window.location.pathname + window.location.search);

if (parsed.kind === 'error') {
  // Every dead-link case GoTrue signals -- expired, already used, tampered --
  // arrives here. The user cannot fix any of them, so send them to the one
  // person who can issue a fresh link.
  showFatal(
    'This link has expired',
    'Invite and password links can only be used once, and expire after a while. Ask your director to send you a new invite.',
  );
} else if (parsed.kind === 'missing') {
  showFatal(
    "This link doesn't work",
    'This page needs to be opened from the link in your email. If you typed the address directly, go back to your email and tap the link there.',
  );
} else {
  if (parsed.type === 'recovery') {
    formIntro.textContent = 'Choose a new password for your account.';
  }
  show('form');

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    showFormError('');

    const password = passwordInput.value;
    const validationError = validatePassword(password, confirmationInput.value);
    if (validationError) {
      showFormError(validationError);
      return;
    }

    submitButton.disabled = true;
    submitButton.textContent = 'Setting password…';

    try {
      await setPassword({
        supabaseUrl: SUPABASE_URL,
        anonKey: ANON_KEY,
        accessToken: parsed.accessToken,
        password,
      });

      // Invites only: a recovery user never had must_set_password set.
      // Skipping this on an invite leaves the app bouncing them back to
      // SetPasswordScreen forever -- see api.js for the full explanation.
      if (parsed.type === 'invite') {
        await completePasswordSetup({
          supabaseUrl: SUPABASE_URL,
          anonKey: ANON_KEY,
          accessToken: parsed.accessToken,
        });
      }

      show('success');
    } catch (error) {
      showFormError(error.message || 'Something went wrong. Please try again.');
      submitButton.disabled = false;
      submitButton.textContent = 'Set password';
    }
  });
}
```

- [ ] **Step 5: Verify the page locally**

Run: `python -m http.server 8000 --directory web`

Then in a browser:
1. `http://localhost:8000/#access_token=fake&type=invite` → password form appears, and the address bar drops the fragment.
2. Enter `abc12` twice, submit → inline "At least 6 characters", no network request.
3. Enter `secret123` and `secret124`, submit → inline "Passwords do not match".
4. Enter `secret123` twice, submit → fails with a real Supabase error (the token is fake). This is correct — it proves the request is being made and the error surfaces.
5. `http://localhost:8000/#error=access_denied&error_code=otp_expired` → "This link has expired".
6. `http://localhost:8000/` → "This link doesn't work".

Stop the server with Ctrl+C.

- [ ] **Step 6: Commit**

```bash
git add web/index.html web/styles.css web/config.js web/main.js
git commit -m "feat(web): set-password page markup, styles, and wiring"
```

---

### Task 4: Deploy to Cloudflare Pages and point DNS

The page must be live before anything is repointed at it.

**Files:**
- Create: `docs/cloudflare-pages-setup.md`

**Interfaces:**
- Consumes: the `web/` directory from Task 3.
- Produces: a working `https://kids.akmalcodes.quest/`.

- [ ] **Step 1: Create the Pages project and deploy**

These steps happen in a browser, not in the terminal.

1. Sign up for a free Cloudflare account at `https://dash.cloudflare.com/sign-up`.
2. In the dashboard, go to **Workers & Pages** → **Create** → **Pages** → **Upload assets**.
3. Name the project `kids-management`.
4. Upload the contents of the `web/` directory (the files themselves, not the folder).
5. Deploy, then note the assigned address, which looks like `kids-management.pages.dev`.
6. Open that `.pages.dev` address and confirm the page loads and shows "This link doesn't work" (correct — there is no fragment).

- [ ] **Step 2: Register the custom domain in Cloudflare — before touching DNS**

In the Pages project → **Custom domains** → **Set up a custom domain** → enter `kids.akmalcodes.quest`.

Cloudflare will say it is waiting for DNS. That is expected; the next step provides it.

**This step must come before Step 3.** Adding the CNAME first, while Cloudflare has no record of the domain, produces a **522 error** — the record points at Cloudflare with nothing on the other side claiming it.

- [ ] **Step 3: Add the CNAME at Porkbun**

1. Log into Porkbun, find `akmalcodes.quest`, click the **DNS** icon.
2. **+ Add record**:
   - Type: **CNAME**
   - Host: `kids` (Porkbun appends `.akmalcodes.quest` automatically)
   - Answer / Value: the `.pages.dev` address from Step 1 (e.g. `kids-management.pages.dev`)
   - TTL: leave the default (600)
3. Save.

This adds one record. It does **not** move nameservers, so the existing Mailgun SPF, DKIM, and tracking records are untouched.

- [ ] **Step 4: Verify DNS and the certificate**

Run: `nslookup -type=CNAME kids.akmalcodes.quest`
Expected: resolves to the `.pages.dev` address.

Run: `curl -sI https://kids.akmalcodes.quest/ | head -1`
Expected: `HTTP/2 200`. A 522 means Step 2 was skipped or has not finished. Certificate issuance can take a few minutes; retry before assuming failure.

Then open `https://kids.akmalcodes.quest/` in a browser and confirm the page renders over https.

- [ ] **Step 5: Write the setup document**

`CLAUDE.md` requires DNS and hosting work to get its own step-by-step, explain-as-you-go document, in the style of `docs/mailgun-porkbun-domain-setup.md`.

Create `docs/cloudflare-pages-setup.md` covering:
- Why the page exists at all (custom schemes have no fallback when the app is absent).
- What Cloudflare Pages is, in one paragraph, for someone who has not used static hosting.
- Why a **subdomain** and not the bare domain: apex domains would require moving nameservers away from Porkbun, which would drag the Mailgun records along with them.
- The exact click-path from Steps 1–3 above, with the real project name and record values used.
- The 522 trap and why ordering matters.
- How to redeploy after editing files in `web/`.
- A pointer to the design spec.

- [ ] **Step 6: Commit**

```bash
git add docs/cloudflare-pages-setup.md
git commit -m "docs: Cloudflare Pages + Porkbun setup for the set-password page"
```

---

### Task 5: Update Supabase auth configuration

Allow-list the new URL and retire `localhost:3000` as the fallback. Still no email repointing — that is Task 6.

**Files:**
- None in the repo. Dashboard configuration plus a verification command.

**Interfaces:**
- Consumes: the live page from Task 4.
- Produces: GoTrue that honours `redirect_to=https://kids.akmalcodes.quest/`.

- [ ] **Step 1: Add the redirect URL**

Supabase dashboard → project `kids-management` → **Authentication** → **URL Configuration** → **Redirect URLs** → **Add URL**:

```
https://kids.akmalcodes.quest/
```

Exact, no wildcard. The redirect target is the root URL, so a wildcard would only widen what an attacker could redirect to.

Do **not** remove `com.example.kidsmanagement://login-callback/` yet — the currently deployed Edge Function still uses it, and removing it now breaks invites until Task 6 lands.

- [ ] **Step 2: Update the Site URL**

Same page → **Site URL**: change `http://localhost:3000` to:

```
https://kids.akmalcodes.quest/
```

Site URL is where GoTrue sends anyone whose `redirect_to` is missing or fails validation. `localhost:3000` is a dead end for a real user; the set-password page at least renders a comprehensible message.

Click **Save changes**.

- [ ] **Step 3: Verify GoTrue honours the new URL**

This is the check that would have caught the underscore bug immediately.

```bash
enc=$(python -c "import urllib.parse;print(urllib.parse.quote('https://kids.akmalcodes.quest/',safe=''))")
curl -s -o /dev/null -D - \
  "https://rpefksoutqsbreiyppee.supabase.co/auth/v1/verify?type=invite&token=bogus&redirect_to=$enc" \
  | grep -i "^location:"
```

Expected: `Location: https://kids.akmalcodes.quest/#error=access_denied&error_code=otp_expired&...`

The `error=` part is correct — the token is deliberately bogus. What matters is the **host**: it must be `kids.akmalcodes.quest`, not `localhost:3000`. A `localhost` answer means Step 1 did not save.

- [ ] **Step 4: Confirm the page handles that exact URL**

Paste the full `Location` value from Step 3 into a browser.
Expected: the page shows "This link has expired" — proving Task 3's error branch works against a real GoTrue response rather than a hand-written fragment.

There is nothing to commit in this task; the changes live in the Supabase dashboard.

---

### Task 6: Repoint invite and recovery emails at the page

**Files:**
- Modify: `supabase/functions/create-user/index.ts:118` and `:136`
- Modify: `lib/core/auth/auth_controller.dart:57-60`
- Test: `test/core/auth/auth_controller_test.dart`

**Interfaces:**
- Consumes: the verified redirect from Task 5.
- Produces: emails whose links land on the page.

- [ ] **Step 1: Write the failing Dart test**

Add to the `AuthController` group in `test/core/auth/auth_controller_test.dart`:

```dart
    test('sendPasswordReset points recovery links at the web set-password page', () async {
      when(() => mockAuth.resetPasswordForEmail(
            any(),
            redirectTo: any(named: 'redirectTo'),
          )).thenAnswer((_) async {});

      await service.sendPasswordReset('jane@example.com');

      verify(() => mockAuth.resetPasswordForEmail(
            'jane@example.com',
            redirectTo: 'https://kids.akmalcodes.quest/',
          )).called(1);
    });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/auth/auth_controller_test.dart`
Expected: FAIL — the verify does not match, because the current value is `com.example.kidsmanagement://login-callback/`.

- [ ] **Step 3: Update the Dart client**

In `lib/core/auth/auth_controller.dart`, replace the `sendPasswordReset` block (currently lines 52–60, including the underscore comment added when the scheme was last changed) with:

```dart
  // Sends a password-recovery email. The link goes to the web set-password
  // page rather than a deep link into the app: a custom URL scheme has no
  // fallback when the app is not installed, and you cannot know before the
  // click whether it is. See
  // docs/superpowers/specs/2026-08-24-web-set-password-page-design.md.
  Future<void> sendPasswordReset(String email) => _client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'https://kids.akmalcodes.quest/',
      );
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/auth/auth_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Update the Edge Function**

In `supabase/functions/create-user/index.ts`, change the `generateLink` option at line 118:

```ts
        redirectTo: "https://kids.akmalcodes.quest/",
```

And the reconstructed link at line 136:

```ts
    encodeURIComponent("https://kids.akmalcodes.quest/")
```

Then replace the comment block above that link (the one explaining the underscore bug) with:

```ts
  // Build the verify URL ourselves rather than using action_link directly.
  // hashed_token + verification_type are exactly what action_link is built
  // from (per GoTrue's own doc comment:
  // auth/v1/verify?type={verification_type}&token={hashed_token}&redirect_to={redirect_to}),
  // so reconstructing it here lets us control the redirect explicitly.
  //
  // The target is the web set-password page, not a deep link into the app: a
  // custom URL scheme silently dead-ends when the app is not installed, which
  // is every desktop click and every not-yet-installed phone. The page works
  // everywhere and clears must_set_password itself.
```

- [ ] **Step 6: Deploy the Edge Function**

A stale deployment has already caused one production bug. Editing the file changes nothing until this runs.

```bash
npx supabase functions deploy create-user --project-ref rpefksoutqsbreiyppee --use-api
```

Expected: `"message":"Deployed Functions."`

Confirm the version incremented:

```bash
npx supabase functions list --project-ref rpefksoutqsbreiyppee
```

Expected: `version` is higher than it was before this task.

- [ ] **Step 7: Run the full Flutter suite**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and `All tests passed!`

- [ ] **Step 8: End-to-end test with a real invite**

This is the row that catches a missing `complete_password_setup` call.

1. In the app, sign in as a director and invite a parent, using an email inbox you control.
2. Open the email **in a desktop browser** and click the link.
3. Confirm it lands on `https://kids.akmalcodes.quest/` with the password form.
4. Set a password.
5. Confirm the success screen.
6. Open the app on the device, sign in as that new parent with the new password.
7. **Confirm you land in the app proper, not back on the set-password screen.** Being re-prompted means `complete_password_setup` was not called or failed.

- [ ] **Step 9: Test link reuse and the recovery path**

Two remaining rows from the spec's manual matrix.

**Reused link:** click the same invite link from Step 8 a second time.
Expected: the page shows "This link has expired" — GoTrue consumed the one-time token on first use, so it now redirects with `error_code=otp_expired`.

**Recovery link:** in the app, open "Forgot password?" and request a reset for the account you just created. Open that email in a desktop browser.
Expected: the page shows "Choose a **new** password for your account." (the recovery wording from Task 3), sets the password, and shows the success screen.

Then sign into the app with the newly reset password.
Expected: straight into the app. If this lands on the set-password screen, `complete_password_setup` is being called on the recovery path when it should be skipped — check the `parsed.type === 'invite'` guard in `main.js`.

- [ ] **Step 10: Commit**

```bash
git add lib/core/auth/auth_controller.dart supabase/functions/create-user/index.ts test/core/auth/auth_controller_test.dart
git commit -m "feat: point invite and recovery emails at the web set-password page"
```

---

### Task 7: Delete the dead custom-scheme registration

With nothing sending to the scheme, the registration is an unused attack surface. Removing it retires security finding **H1**.

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml:28-50`
- Modify: `ios/Runner/Info.plist:31-45`
- Modify: `lib/features/auth/forgot_password_screen.dart:6-10`
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/specs/2026-07-01-childcare-management-design.md`

**Interfaces:**
- Consumes: the working flow from Task 6. Do not start this task until Task 6 Step 8 passes.
- Produces: no scheme registration anywhere.

- [ ] **Step 1: Remove the Android intent-filter**

In `android/app/src/main/AndroidManifest.xml`, delete the entire deep-link comment block and its `<intent-filter>` — everything from `<!-- Deep link for Supabase auth callbacks` through the `</intent-filter>` that follows it. Leave the LAUNCHER intent-filter above it alone.

- [ ] **Step 2: Remove the iOS URL type**

In `ios/Runner/Info.plist`, delete the deep-link comment and the `CFBundleURLTypes` key together with its `<array>` value.

- [ ] **Step 3: Update the stale comment**

In `lib/features/auth/forgot_password_screen.dart`, replace the header comment with:

```dart
// Sends a password-recovery email. The link opens the web set-password page
// (https://kids.akmalcodes.quest/), which sets the password directly in the
// browser -- so this flow no longer re-enters the app at all, and this screen's
// only job is capturing the email and kicking off the send.
```

- [ ] **Step 4: Rewrite the CLAUDE.md section**

Replace the "Auth deep-link scheme — do not add an underscore" section with:

```markdown
## Auth callbacks go to a web page, not a deep link

Invite and password-recovery emails point at `https://kids.akmalcodes.quest/`
(see `docs/superpowers/specs/2026-08-24-web-set-password-page-design.md` and
`docs/cloudflare-pages-setup.md`). The page sets the password in the browser
and clears `must_set_password` itself.

There is no longer any custom URL scheme registered. Do not reintroduce one
without reading the history below.

**Why the scheme was abandoned.** It was `com.example.kids_management://`, and
it never worked — not before the rename either. RFC 3986 allows only letters,
digits, `+`, `-` and `.` in a URI scheme. Supabase Auth (GoTrue, Go) parses
`redirect_to` with Go's `net/url`, which finds no scheme at all in a string
containing `_`; validation then fails and GoTrue **silently** falls back to the
Site URL. No error is raised anywhere. That cost two debugging sessions and was
once misdiagnosed as a Supabase SDK bug.

Even underscore-free, a custom scheme has no fallback: it dead-ends on every
desktop click and on any phone without the app installed. That is why the https
page replaced it rather than the scheme merely being renamed. Removing the
scheme also retired security finding H1 — an unverified scheme can be
registered by any app, which made invite tokens interceptable.

If a future change repoints auth emails, remember the deployed Edge Function is
a separate artifact: after editing `create-user`, redeploy it
(`npx supabase functions deploy create-user --project-ref rpefksoutqsbreiyppee
--use-api`) or the old value keeps being sent.
```

- [ ] **Step 5: Update the main design spec**

In `docs/superpowers/specs/2026-07-01-childcare-management-design.md`:

- §6.6a: replace the two sentences beginning "The invite email's link deep-links back into the app…" and ending "…see the 'Auth deep-link scheme' section of `CLAUDE.md`." with:

  > The invite email's link opens the web set-password page at `https://kids.akmalcodes.quest/` (static site on Cloudflare Pages; see the 2026-08-24 design spec). A custom URL scheme was used originally but dead-ended on every desktop click and on any phone without the app installed, with no possible fallback. The page sets the password through GoTrue's REST API and then calls the same `complete_password_setup()` RPC the app used to, so the invited user signs into the app normally rather than being routed to `SetPasswordScreen`.
- §6.7a: replace the `com.example.kidsmanagement://login-callback/` reference with `https://kids.akmalcodes.quest/`.
- The `applicationId` rename item: drop the deep-link scheme from the list of things that must move together — it no longer exists. Keep the `applicationId` rename itself.
- **H1**: mark resolved, noting it was retired by deleting the scheme registration rather than by verifying it, and that App Links remain available later as a UX improvement rather than a security fix.

- [ ] **Step 6: Verify the app still builds and passes**

Run: `flutter analyze && flutter test && flutter build apk --debug`
Expected: `No issues found!`, `All tests passed!`, `Built build\app\outputs\flutter-apk\app-debug.apk`.

Confirm the scheme is gone from the built manifest:

```bash
AAPT=$(ls -d "$HOME/AppData/Local/Android/Sdk/build-tools/"*/aapt2.exe | tail -1)
"$AAPT" dump xmltree build/app/outputs/flutter-apk/app-debug.apk --file AndroidManifest.xml | grep -i "scheme"
```

Expected: no output. Any `com.example.*` scheme means Step 1 did not take.

- [ ] **Step 7: Remove the scheme from the Supabase allow-list**

Supabase dashboard → **Authentication** → **URL Configuration** → **Redirect URLs** → select `com.example.kidsmanagement://login-callback/` → **Remove**.

Confirm only `https://kids.akmalcodes.quest/` remains.

- [ ] **Step 8: Re-run the end-to-end invite test**

Repeat Task 6 Step 8 in full with a fresh invite, on a device running the newly built APK. This confirms removing the scheme broke nothing, since the flow no longer depends on it.

- [ ] **Step 9: Commit**

```bash
git add android/app/src/main/AndroidManifest.xml ios/Runner/Info.plist lib/features/auth/forgot_password_screen.dart CLAUDE.md docs/superpowers/specs/2026-07-01-childcare-management-design.md
git commit -m "security: remove the custom auth URL scheme, retiring H1"
```

---

## Done when

- `https://kids.akmalcodes.quest/` serves over https and handles all five page states.
- `npm test --prefix web` passes (15 tests).
- `flutter analyze` is clean and `flutter test` passes (208 tests — the 207 existing plus the new redirect assertion).
- A real invite, clicked on a desktop browser, sets a password; that user then signs into the app and is **not** returned to the set-password screen.
- No custom URL scheme remains in the Android manifest, the iOS plist, or the Supabase allow-list.
