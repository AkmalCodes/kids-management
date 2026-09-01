import { SUPABASE_URL, ANON_KEY } from './config.js';
import { parseAuthParams, validatePassword } from './auth.js';
import { setPassword, completePasswordSetup, verifyTokenHash } from './api.js';

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

const parsed = parseAuthParams(window.location.search, window.location.hash);

// Strip every auth parameter as soon as it has been read, from BOTH the query
// string and the fragment, so the token stops showing in the address bar,
// browser history, and any shared screen. replaceState rewrites the current
// entry rather than adding one, so Back still works.
//
// The query string matters as much as the fragment now: the email link carries
// token_hash as a query parameter, and unlike a fragment that IS sent to the
// server on every subsequent navigation. Any unrelated parameter is preserved.
{
  const url = new URL(window.location.href);
  for (const key of ['token_hash', 'type', 'access_token', 'refresh_token',
                     'error', 'error_code', 'error_description', 'code']) {
    url.searchParams.delete(key);
  }
  url.hash = '';
  history.replaceState(null, '', url.pathname + (url.search || '') );
}

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
      // A token_hash link carries no session yet -- exchange it now, at submit
      // time. Deferring it to here is deliberate: this call consumes the
      // single-use token, and doing it on page load would let a mail scanner's
      // prefetch burn the token before the recipient ever typed anything.
      // A legacy fragment link already carries a session, so it skips this.
      const accessToken = parsed.kind === 'token_hash'
        ? await verifyTokenHash({
            supabaseUrl: SUPABASE_URL,
            anonKey: ANON_KEY,
            tokenHash: parsed.tokenHash,
            type: parsed.type,
          })
        : parsed.accessToken;

      await setPassword({
        supabaseUrl: SUPABASE_URL,
        anonKey: ANON_KEY,
        accessToken,
        password,
      });

      // Invites only: a recovery user never had must_set_password set.
      // Skipping this on an invite leaves the app bouncing them back to
      // SetPasswordScreen forever -- see api.js for the full explanation.
      if (parsed.type === 'invite') {
        await completePasswordSetup({
          supabaseUrl: SUPABASE_URL,
          anonKey: ANON_KEY,
          accessToken,
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
