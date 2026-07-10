import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_flutter/features/director/director_shell.dart';

void main() {
  testWidgets('DirectorShell renders four tabs', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: DirectorShell())),
    );
    expect(find.text('Teachers'), findsOneWidget);
    expect(find.text('Schedules'), findsOneWidget);
    expect(find.text('Lesson Plans'), findsOneWidget);
    expect(find.text('Attendance'), findsOneWidget);
  });
}
