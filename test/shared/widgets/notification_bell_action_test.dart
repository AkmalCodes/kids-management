import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/core/models/app_notification.dart';
import 'package:kids_management/core/controllers/notification_controller.dart';
import 'package:kids_management/shared/screens/notifications_screen.dart';
import 'package:kids_management/shared/widgets/notification_bell_action.dart';

AppNotification _notification(String id, {bool read = false}) => AppNotification(
      id: id,
      userId: 'u-1',
      type: 'lesson_plan',
      status: 'SUBMITTED',
      title: 'Lesson plan submitted',
      body: 'body',
      entityId: 'lp-1',
      readAt: read ? DateTime(2026, 9, 15) : null,
      createdAt: DateTime(2026, 9, 15),
    );

Future<void> _pump(WidgetTester tester, List<AppNotification> data) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [notificationsProvider.overrideWith((ref) => Stream.value(data))],
      // No `const` here: AppBar has no const constructor.
      child: MaterialApp(
        home: Scaffold(appBar: AppBar(actions: const [NotificationBellAction(isDirector: true)])),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows no badge label when there are no unread notifications', (tester) async {
    await _pump(tester, []);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('shows the unread count on the badge, ignoring read rows', (tester) async {
    await _pump(tester, [
      _notification('n-1'),
      _notification('n-2'),
      _notification('n-3', read: true),
    ]);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('tapping the bell opens NotificationsScreen', (tester) async {
    await _pump(tester, []);
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsScreen), findsOneWidget);
  });
}
