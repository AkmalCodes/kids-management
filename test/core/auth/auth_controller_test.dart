import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test_flutter/core/auth/auth_controller.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockSupabaseClient extends Mock implements SupabaseClient {}

void main() {
  late MockGoTrueClient mockAuth;
  late MockSupabaseClient mockClient;
  late AuthController service;

  setUp(() {
    mockAuth = MockGoTrueClient();
    mockClient = MockSupabaseClient();
    when(() => mockClient.auth).thenReturn(mockAuth);
    service = AuthController(client: mockClient);
  });

  group('AuthController', () {
    test('signIn calls signInWithPassword', () async {
      when(() => mockAuth.signInWithPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      )).thenAnswer((_) async => AuthResponse());

      await service.signIn('test@test.com', 'password123');

      verify(() => mockAuth.signInWithPassword(
        email: 'test@test.com',
        password: 'password123',
      )).called(1);
    });

    test('signOut calls supabase auth signOut', () async {
      when(() => mockAuth.signOut()).thenAnswer((_) async {});

      await service.signOut();

      verify(() => mockAuth.signOut()).called(1);
    });
  });
}
