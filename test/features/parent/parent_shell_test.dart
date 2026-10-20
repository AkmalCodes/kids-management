import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawankecil/features/parent/parent_shell.dart';
import 'package:kawankecil/features/parent/screens/child_attendance_screen.dart';
import 'package:kawankecil/features/parent/screens/child_schedule_screen.dart';

void main() {
  testWidgets('ParentShell renders Schedule, Attendance, Reports and Profile tabs',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ParentShell())),
    );
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Attendance'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.byType(ChildScheduleScreen), findsOneWidget);
  });

  testWidgets('tapping Attendance tab switches body', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ParentShell())),
    );
    await tester.tap(find.text('Attendance'));
    await tester.pump();
    expect(find.byType(ChildAttendanceScreen), findsOneWidget);
  });
}
