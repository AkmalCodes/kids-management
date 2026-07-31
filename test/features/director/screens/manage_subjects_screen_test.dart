import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/auth/auth_service.dart';
import 'package:test_flutter/core/models/app_user.dart';
import 'package:test_flutter/core/models/subject.dart';
import 'package:test_flutter/core/services/subject_service.dart';
import 'package:test_flutter/features/director/screens/manage_subjects_screen.dart';

class MockSubjectService extends Mock implements SubjectService {}

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

Subject _subject(String id, String name) => Subject(
  id: id,
  centerId: 'center-1',
  name: name,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

void main() {
  late MockSubjectService mockSubjects;

  setUp(() {
    mockSubjects = MockSubjectService();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(_director())),
          subjectServiceProvider.overrideWithValue(mockSubjects),
        ],
        child: const MaterialApp(home: ManageSubjectsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists subjects, and empty state when none', (tester) async {
    when(() => mockSubjects.fetchAll()).thenAnswer((_) async => []);
    await pumpScreen(tester);
    expect(find.text('No subjects yet.'), findsOneWidget);
  });

  testWidgets('creating a subject calls createSubject and refreshes', (tester) async {
    when(() => mockSubjects.fetchAll()).thenAnswer((_) async => []);
    when(() => mockSubjects.createSubject(
          name: any(named: 'name'),
          color: any(named: 'color'),
          centerId: any(named: 'centerId'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => _subject('sub-1', 'Art'));

    await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Art');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(() => mockSubjects.createSubject(
          name: 'Art',
          centerId: 'center-1',
          actorUid: 'director-1',
        )).called(1);
  });
}
