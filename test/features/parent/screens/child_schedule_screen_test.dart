import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/auth/auth_service.dart';
import 'package:test_flutter/core/models/app_user.dart';
import 'package:test_flutter/core/models/child.dart';
import 'package:test_flutter/core/services/child_service.dart';
import 'package:test_flutter/core/services/schedule_service.dart';
import 'package:test_flutter/features/parent/screens/child_schedule_screen.dart';

class MockChildService extends Mock implements ChildService {}

AppUser _parent() => AppUser(
  id: 'parent-1',
  role: 'parent',
  name: 'Parent',
  phone: '',
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

Child _child({String? classId}) => Child(
  id: 'child-1',
  name: 'Alice',
  dob: DateTime(2022, 1, 1),
  centerId: 'center-1',
  className: '',
  teacherId: 'teacher-1',
  classId: classId,
  allergies: '',
  notes: '',
  enrolledAt: DateTime(2026),
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

void main() {
  late MockChildService mockChildren;

  setUp(() {
    mockChildren = MockChildService();
  });

  Future<void> pumpScreen(WidgetTester tester, {List<Override> extra = const []}) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => Stream.value(_parent())),
            childServiceProvider.overrideWithValue(mockChildren),
            ...extra,
          ],
          child: const MaterialApp(home: Scaffold(body: ChildScheduleScreen())),
        ),
      );

  testWidgets('shows a message when no children are linked', (tester) async {
    when(() => mockChildren.fetchForParent('parent-1')).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('No children linked to your account yet.'), findsOneWidget);
  });

  testWidgets('prompts to assign a class when the child has none', (tester) async {
    when(() => mockChildren.fetchForParent('parent-1'))
        .thenAnswer((_) async => [_child(classId: null)]);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Not assigned to a class yet.'), findsOneWidget);
  });

  testWidgets("shows the child's class schedule", (tester) async {
    when(() => mockChildren.fetchForParent('parent-1'))
        .thenAnswer((_) async => [_child(classId: 'class-1')]);

    await pumpScreen(
      tester,
      extra: [
        // Schedule belongs to the class (type: class).
        scheduleEntriesProvider((type: 'class', refId: 'class-1'))
            .overrideWith((ref) async => []),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.byTooltip('Month view'), findsOneWidget);
    expect(find.text('No events'), findsWidgets);
  });
}
