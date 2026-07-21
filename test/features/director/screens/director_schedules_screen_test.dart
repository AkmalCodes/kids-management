import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/models/app_user.dart';
import 'package:test_flutter/core/services/teacher_service.dart';
import 'package:test_flutter/features/director/screens/director_schedules_screen.dart';
import 'package:test_flutter/features/director/screens/person_schedule_screen.dart';

class MockTeacherService extends Mock implements TeacherService {}

AppUser _teacher(String id, String name) => AppUser(
  id: id,
  role: 'teacher',
  name: name,
  phone: '',
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

void main() {
  late MockTeacherService mockTeachers;

  setUp(() {
    mockTeachers = MockTeacherService();
  });

  Future<void> pumpScreen(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: [teacherServiceProvider.overrideWithValue(mockTeachers)],
          child: const MaterialApp(
            home: Scaffold(body: DirectorSchedulesScreen()),
          ),
        ),
      );

  testWidgets('shows all teachers with no Children tab', (tester) async {
    when(() => mockTeachers.fetchAll()).thenAnswer(
      (_) async => [_teacher('teacher-1', 'Ms. Smith'), _teacher('teacher-2', 'Mr. Jones')],
    );

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Ms. Smith'), findsOneWidget);
    expect(find.text('Mr. Jones'), findsOneWidget);
    expect(find.text('Children'), findsNothing);
  });

  testWidgets('tapping the search icon reveals a search field', (tester) async {
    when(() => mockTeachers.fetchAll())
        .thenAnswer((_) async => [_teacher('teacher-1', 'Ms. Smith')]);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('typing a query filters the teacher list by name', (tester) async {
    when(() => mockTeachers.fetchAll()).thenAnswer(
      (_) async => [_teacher('teacher-1', 'Ms. Smith'), _teacher('teacher-2', 'Mr. Jones')],
    );

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'smith');
    await tester.pumpAndSettle();

    expect(find.text('Ms. Smith'), findsOneWidget);
    expect(find.text('Mr. Jones'), findsNothing);
  });

  testWidgets('closing search clears the query and restores the full list', (tester) async {
    when(() => mockTeachers.fetchAll()).thenAnswer(
      (_) async => [_teacher('teacher-1', 'Ms. Smith'), _teacher('teacher-2', 'Mr. Jones')],
    );

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'smith');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Ms. Smith'), findsOneWidget);
    expect(find.text('Mr. Jones'), findsOneWidget);
  });

  testWidgets('tapping a teacher opens their PersonScheduleScreen', (tester) async {
    when(() => mockTeachers.fetchAll())
        .thenAnswer((_) async => [_teacher('teacher-1', 'Ms. Smith')]);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ms. Smith'));
    await tester.pumpAndSettle();

    final screen = tester.widget<PersonScheduleScreen>(find.byType(PersonScheduleScreen));
    expect(screen.title, 'Ms. Smith');
    expect(screen.type, 'teacher');
    expect(screen.refId, 'teacher-1');
    expect(screen.centerId, 'center-1');
  });
}
