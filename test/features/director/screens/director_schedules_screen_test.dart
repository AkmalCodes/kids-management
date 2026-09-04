import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kids_management/core/models/class_group.dart';
import 'package:kids_management/core/controllers/class_controller.dart';
import 'package:kids_management/features/director/screens/director_schedules_screen.dart';
import 'package:kids_management/features/director/screens/person_schedule_screen.dart';

class MockClassController extends Mock implements ClassController {}

ClassGroup _classGroup(String id, String name) => ClassGroup(
  id: id,
  name: name,
  teacherIds: const ['teacher-1'],
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

void main() {
  late MockClassController mockClasses;

  setUp(() {
    mockClasses = MockClassController();
  });

  Future<void> pumpScreen(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: [classControllerProvider.overrideWithValue(mockClasses)],
          child: const MaterialApp(
            home: Scaffold(body: DirectorSchedulesScreen()),
          ),
        ),
      );

  testWidgets('lists all classes', (tester) async {
    when(() => mockClasses.fetchAll()).thenAnswer(
      (_) async => [_classGroup('class-1', 'Sunflowers'), _classGroup('class-2', 'Daisies')],
    );

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Sunflowers'), findsOneWidget);
    expect(find.text('Daisies'), findsOneWidget);
  });

  testWidgets('tapping the search icon reveals a search field', (tester) async {
    when(() => mockClasses.fetchAll()).thenAnswer((_) async => [_classGroup('class-1', 'Sunflowers')]);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('typing a query filters classes by name', (tester) async {
    when(() => mockClasses.fetchAll()).thenAnswer(
      (_) async => [_classGroup('class-1', 'Sunflowers'), _classGroup('class-2', 'Daisies')],
    );

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'sun');
    await tester.pumpAndSettle();

    expect(find.text('Sunflowers'), findsOneWidget);
    expect(find.text('Daisies'), findsNothing);
  });

  testWidgets('tapping a class opens its PersonScheduleScreen (type=class)', (tester) async {
    when(() => mockClasses.fetchAll())
        .thenAnswer((_) async => [_classGroup('class-1', 'Sunflowers')]);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sunflowers'));
    await tester.pumpAndSettle();

    final screen = tester.widget<PersonScheduleScreen>(find.byType(PersonScheduleScreen));
    expect(screen.title, 'Sunflowers');
    expect(screen.type, 'class');
    expect(screen.refId, 'class-1');
    expect(screen.centerId, 'center-1');
  });
}
