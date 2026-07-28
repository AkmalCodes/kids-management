import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/auth/auth_service.dart';
import 'package:test_flutter/core/models/app_user.dart';
import 'package:test_flutter/core/models/child.dart';
import 'package:test_flutter/core/services/child_service.dart';
import 'package:test_flutter/core/services/daily_report_service.dart';
import 'package:test_flutter/features/teacher/screens/daily_report_edit_screen.dart';
import 'package:test_flutter/features/teacher/screens/teacher_reports_screen.dart';

class MockChildService extends Mock implements ChildService {}

class MockDailyReportService extends Mock implements DailyReportService {}

AppUser _teacher() => AppUser(
  id: 'teacher-1',
  role: 'teacher',
  name: 'Teacher',
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
  dob: DateTime(2022, 1, 1),
  centerId: 'center-1',
  className: '',
  teacherId: 'teacher-1',
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
  late MockDailyReportService mockReports;

  setUp(() {
    mockChildren = MockChildService();
    mockReports = MockDailyReportService();
    // The editor (opened on tap) loads any existing report in initState.
    when(() => mockReports.fetchForChildAndDate(any(), any())).thenAnswer((_) async => null);
  });

  Future<void> pumpScreen(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => Stream.value(_teacher())),
            childServiceProvider.overrideWithValue(mockChildren),
            dailyReportServiceProvider.overrideWithValue(mockReports),
          ],
          child: const MaterialApp(home: Scaffold(body: TeacherReportsScreen())),
        ),
      );

  testWidgets('shows a message when the teacher has no children', (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('No children assigned to you yet.'), findsOneWidget);
  });

  testWidgets('lists children and opens the editor on tap', (tester) async {
    when(() => mockChildren.fetchForTeacher('teacher-1')).thenAnswer((_) async => [_child()]);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    final screen = tester.widget<DailyReportEditScreen>(find.byType(DailyReportEditScreen));
    expect(screen.child.id, 'child-1');
  });
}
