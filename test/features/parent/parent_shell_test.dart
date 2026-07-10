import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_flutter/features/parent/parent_shell.dart';

void main() {
  testWidgets('ParentShell renders Schedule, Attendance and Reports tabs', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ParentShell())),
    );
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Attendance'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
  });

  testWidgets('tapping Attendance tab switches body', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ParentShell())),
    );
    await tester.tap(find.text('Attendance'));
    await tester.pump();
    expect(find.text('Attendance — coming soon'), findsOneWidget);
  });
}
