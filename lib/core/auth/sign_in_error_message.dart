import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

// Shown whenever the phone can't talk to Supabase at all (offline, DNS
// failure, timeout). Public so the shared error view can reuse the wording.
const kServerUnreachableMessage =
    "Can't reach the server. Check your connection.";

// Turns whatever signInWithPassword threw into a message for the login
// screen.
//
// Why not just always say "Invalid email or password"? That used to be the
// only message, and it lied whenever the real cause was something else:
// no internet, or a build started without its Supabase --dart-define values
// (e.g. `flutter run --profile` from a terminal). The user then retypes a
// correct password over and over. Only Supabase *rejecting the credentials*
// earns the "invalid" message.
String signInErrorMessage(Object error) {
  // AuthRetryableFetchException is the Supabase client's own wrapper for
  // "the request never got an answer", so check it before AuthException
  // (it's a subclass of AuthException).
  if (error is AuthRetryableFetchException ||
      error is SocketException ||
      error is TimeoutException) {
    return kServerUnreachableMessage;
  }
  if (error is AuthException) {
    // `code` is GoTrue's machine-readable reason. The message check covers
    // older Supabase servers that only sent the text.
    if (error.code == 'invalid_credentials' ||
        error.message == 'Invalid login credentials') {
      return 'Invalid email or password. Please try again.';
    }
    if (error.code == 'email_not_confirmed') {
      return 'This email is not confirmed yet. Use the link in your invite email first.';
    }
  }
  return 'Sign-in failed. Please try again.';
}
