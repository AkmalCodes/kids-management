import 'package:flutter_test/flutter_test.dart';
import 'package:kawankecil/core/app_config.dart';

void main() {
  test('nothing missing when both defines are set', () {
    expect(missingSupabaseDefines(url: 'https://x.supabase.co', anonKey: 'k'),
        isEmpty);
  });

  test('lists each missing define by name', () {
    expect(missingSupabaseDefines(url: '', anonKey: ''),
        ['SUPABASE_URL', 'SUPABASE_ANON_KEY']);
    expect(missingSupabaseDefines(url: 'https://x.supabase.co', anonKey: ''),
        ['SUPABASE_ANON_KEY']);
  });

  testWidgets('MissingConfigApp names the missing defines', (tester) async {
    await tester.pumpWidget(const MissingConfigApp(missing: ['SUPABASE_URL']));

    expect(find.textContaining('SUPABASE_URL'), findsWidgets);
    expect(find.textContaining('--dart-define'), findsWidgets);
  });
}
