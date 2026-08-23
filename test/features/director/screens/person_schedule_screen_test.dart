import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/core/controllers/schedule_controller.dart';
import 'package:kids_management/features/director/screens/person_schedule_screen.dart';

void main() {
  testWidgets('shows the title and the agenda view once entries load', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleEntriesProvider((type: 'teacher', refId: 'teacher-1'))
              .overrideWith((ref) async => []),
        ],
        child: const MaterialApp(
          home: PersonScheduleScreen(
            title: 'Ms. Smith',
            type: 'teacher',
            refId: 'teacher-1',
            centerId: 'center-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ms. Smith'), findsOneWidget);
    // Proves ScheduleAgendaView actually rendered (its month/week toggle).
    expect(find.byTooltip('Month view'), findsOneWidget);
  });
}
