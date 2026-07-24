import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/auth/auth_service.dart';
import 'package:test_flutter/core/models/app_user.dart';
import 'package:test_flutter/core/models/child.dart';
import 'package:test_flutter/core/services/child_service.dart';
import 'package:test_flutter/core/services/teacher_service.dart';
import 'package:test_flutter/features/director/screens/child_detail_screen.dart';

class MockChildService extends Mock implements ChildService {}

class MockTeacherService extends Mock implements TeacherService {}

class FakeChild extends Fake implements Child {}

AppUser _director() => AppUser(
  id: 'director-1',
  role: 'director',
  name: 'Director',
  phone: '',
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

Child _child() => Child(
  id: 'child-1',
  name: 'Alice',
  dob: DateTime(2022, 6, 1),
  centerId: 'center-1',
  className: 'Class A',
  teacherId: null,
  allergies: 'Peanuts',
  notes: '',
  enrolledAt: DateTime(2026),
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

void main() {
  setUpAll(() {
    registerFallbackValue(FakeChild());
  });

  late MockChildService mockChildren;
  late MockTeacherService mockTeachers;

  setUp(() {
    mockChildren = MockChildService();
    mockTeachers = MockTeacherService();
    when(() => mockTeachers.fetchAll()).thenAnswer((_) async => []);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(_director())),
          childServiceProvider.overrideWithValue(mockChildren),
          teacherServiceProvider.overrideWithValue(mockTeachers),
        ],
        child: MaterialApp(home: ChildDetailScreen(child: _child())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('pre-fills the existing details and shows the age', (tester) async {
    await pumpScreen(tester);

    expect(find.widgetWithText(TextFormField, 'Alice'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Class A'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Peanuts'), findsOneWidget);
    // Born 2022-06-01; current test date is 2026, so age is 3 or 4.
    expect(find.textContaining('Age '), findsOneWidget);
  });

  testWidgets('saving writes the edited fields via updateChild', (tester) async {
    when(() => mockChildren.updateChild(any())).thenAnswer((_) async => _child());

    await pumpScreen(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Alice'), 'Alice B');
    await tester.enterText(find.widgetWithText(TextFormField, 'Class A'), 'Class B');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final saved = verify(() => mockChildren.updateChild(captureAny())).captured.single as Child;
    expect(saved.id, 'child-1');
    expect(saved.name, 'Alice B');
    expect(saved.className, 'Class B');
    expect(saved.allergies, 'Peanuts');
    expect(saved.updatedBy, 'director-1');
  });

  testWidgets('shows an error and does not pop when saving fails', (tester) async {
    when(() => mockChildren.updateChild(any())).thenThrow(Exception('rls denied'));

    await pumpScreen(tester);

    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not save changes'), findsOneWidget);
    expect(find.byType(ChildDetailScreen), findsOneWidget);
  });
}
