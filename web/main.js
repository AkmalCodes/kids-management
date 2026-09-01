import { SUPABASE_URL, ANON_KEY } from './config.js';
import { parseAuthParams, validateFields, createSessionProvider } from './auth.js';
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
const passwordError = document.getElementById('password-error');
const confirmationError = document.getElementById('confirmation-error');
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

// Paints one field's error state. aria-invalid drives both the ring colour
// (see styles.css) and what a screen reader announces, so the two cannot
// disagree.
function showFieldError(input, node, message) {
  node.textContent = message || '';
  node.hidden = !message;
  if (message) {
    input.setAttribute('aria-invalid', 'true');
  } else {
    input.removeAttribute('aria-invalid');
  }
}

function clearAllErrors() {
  showFieldError(passwordInput, passwordError, null);
  showFieldError(confirmationInput, confirmationError, null);
  showFormError('');
}

// Returns true when the form may be submitted. Called on submit, and again on
// every keystroke once the user has attempted a submit -- errors that appear
// before someone has finished typing are just nagging, but once they have been
// shown, they should clear the moment the input becomes valid.
let hasAttemptedSubmit = false;
function validateForm() {
  const { password: pwError, confirmation: cfError } =
    validateFields(passwordInput.value, confirmationInput.value);
  showFieldError(passwordInput, passwordError, pwError);
  showFieldError(confirmationInput, confirmationError, cfError);
  return !pwError && !cfError;
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

  // A legacy fragment link arrives with a session already; a token_hash link
  // gets one from the first successful verify and reuses it thereafter.
  const getSession = createSessionProvider({
    accessToken: parsed.kind === 'session' ? parsed.accessToken : null,
    verify: () => verifyTokenHash({
      supabaseUrl: SUPABASE_URL,
      anonKey: ANON_KEY,
      tokenHash: parsed.tokenHash,
      type: parsed.type,
    }),
  });

  for (const input of [passwordInput, confirmationInput]) {
    input.addEventListener('input', () => {
      if (hasAttemptedSubmit) validateForm();
    });
  }

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    showFormError('');
    hasAttemptedSubmit = true;

    // Nothing leaves the page until both fields pass. The button stays
    // enabled rather than being disabled while invalid: a dead button gives
    // no reason, whereas clicking it points at the field that needs fixing.
    if (!validateForm()) {
      (passwordError.hidden ? confirmationInput : passwordInput).focus();
      return;
    }

    const password = passwordInput.value;

    submitButton.disabled = true;
    submitButton.textContent = 'Setting password…';

    try {
      // Exchanged at submit time, not on load: this consumes the single-use
      // token, and doing it on load would let a mail scanner's prefetch burn it
      // before the recipient typed anything. getSession() caches the result, so
      // a submit that fails afterwards (a rejected password, say) can be
      // retried without re-verifying an already-spent token.
      const accessToken = await getSession();

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
