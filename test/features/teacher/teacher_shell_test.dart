import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kawankecil/core/controllers/notification_controller.dart';
import 'package:kawankecil/features/teacher/teacher_shell.dart';
import 'package:kawankecil/shared/widgets/app_bottom_nav.dart';

void main() {
  testWidgets('TeacherShell renders its tabs', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // The AppBar's NotificationBellAction watches this; without an
          // override it would reach for the real (uninitialised) Supabase client.
          notificationsProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: const MaterialApp(home: TeacherShell()),
      ),
    );
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Attendance'), findsOneWidget);
    expect(find.text('Lessons'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });
  // The Lessons tab carries the teacher's greeting, so it is the landing tab.
  testWidgets('TeacherShell opens on the Lessons tab', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [notificationsProvider.overrideWith((ref) => Stream.value([]))],
        child: const MaterialApp(home: TeacherShell()),
      ),
    );
    final nav = tester.widget<AppBottomNav>(find.byType(AppBottomNav));
    expect(nav.selectedIndex, 2);
    expect(nav.destinations[2].label, 'Lessons');
  });
}
