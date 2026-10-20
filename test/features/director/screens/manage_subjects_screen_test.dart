import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kawankecil/core/auth/auth_controller.dart';
import 'package:kawankecil/core/models/app_user.dart';
import 'package:kawankecil/core/models/subject.dart';
import 'package:kawankecil/core/controllers/subject_controller.dart';
import 'package:kawankecil/features/director/screens/manage_subjects_screen.dart';

class MockSubjectController extends Mock implements SubjectController {}

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
  late MockSubjectController mockSubjects;

  setUp(() {
    mockSubjects = MockSubjectController();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(_director())),
          subjectControllerProvider.overrideWithValue(mockSubjects),
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

  testWidgets('creating a subject calls createSubject and refreshes the list', (tester) async {
    // Empty first load; after create, the refresh returns the new subject.
    var created = false;
    when(() => mockSubjects.fetchAll())
        .thenAnswer((_) async => created ? [_subject('sub-1', 'Art')] : <Subject>[]);
    when(() => mockSubjects.createSubject(
          name: any(named: 'name'),
          color: any(named: 'color'),
          centerId: any(named: 'centerId'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async {
      created = true;
      return _subject('sub-1', 'Art');
    });

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
    // The refresh (a setState) must not error, and the new subject shows.
    expect(find.textContaining('Could not save'), findsNothing);
    expect(find.text('Art'), findsOneWidget);
  });
}
