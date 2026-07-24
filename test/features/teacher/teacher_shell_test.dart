import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_flutter/features/teacher/teacher_shell.dart';

void main() {
  testWidgets('TeacherShell renders its tabs', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: TeacherShell())),
    );
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Attendance'), findsOneWidget);
    expect(find.text('Lessons'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });
}
