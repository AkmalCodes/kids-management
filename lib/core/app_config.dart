import 'package:flutter/material.dart';

// The Supabase URL and key aren't in the source code. They're passed in at
// build time with `--dart-define=NAME=value` (VS Code adds them from
// .vscode/launch.json). A build started without them, e.g.
// `flutter run --profile` typed in a terminal, used to start normally and
// then fail every sign-in with a misleading "Invalid email or password".
// main() now checks first and shows MissingConfigApp instead.

// Names of the required defines that came in empty, in a stable order.
// Takes the values as parameters (instead of reading String.fromEnvironment
// itself) so tests can pass any combination.
List<String> missingSupabaseDefines({
  required String url,
  required String anonKey,
}) =>
    [
      if (url.isEmpty) 'SUPABASE_URL',
      if (anonKey.isEmpty) 'SUPABASE_ANON_KEY',
    ];

// A bare app shown instead of the real one when config is missing. It must
// not touch Supabase or Riverpod, since neither is set up at this point.
class MissingConfigApp extends StatelessWidget {
  const MissingConfigApp({super.key, required this.missing});

  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.settings_suggest_outlined, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'App started without its server settings',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text('Missing: ${missing.join(', ')}'),
                const SizedBox(height: 12),
                const Text(
                  'Run it from VS Code (launch.json passes them in), or add '
                  'them to the command, e.g.\n'
                  'flutter run --profile --dart-define=SUPABASE_URL=... '
                  '--dart-define=SUPABASE_ANON_KEY=...',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
