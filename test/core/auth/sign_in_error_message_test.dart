import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kawankecil/core/auth/sign_in_error_message.dart';

void main() {
  test('wrong email or password says so', () {
    const e = AuthApiException('Invalid login credentials',
        statusCode: '400', code: 'invalid_credentials');
    expect(signInErrorMessage(e), 'Invalid email or password. Please try again.');
  });

  test('unconfirmed email gets its own message', () {
    const e = AuthApiException('Email not confirmed',
        statusCode: '400', code: 'email_not_confirmed');
    expect(signInErrorMessage(e), contains('not confirmed'));
  });

  test('network failures say the server is unreachable, not "invalid"', () {
    for (final e in <Object>[
      AuthRetryableFetchException(message: 'Failed host lookup'),
      const SocketException('No route to host'),
      TimeoutException('slow'),
    ]) {
      expect(signInErrorMessage(e), kServerUnreachableMessage, reason: '$e');
    }
  });

  test('anything else is a generic failure, not "invalid"', () {
    expect(signInErrorMessage(StateError('boom')),
        'Sign-in failed. Please try again.');
    const server = AuthApiException('Internal error', statusCode: '500');
    expect(signInErrorMessage(server), 'Sign-in failed. Please try again.');
  });
}
