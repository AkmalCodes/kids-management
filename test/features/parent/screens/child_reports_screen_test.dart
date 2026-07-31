import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/auth/auth_service.dart';
import 'package:test_flutter/core/models/app_user.dart';
import 'package:test_flutter/core/models/child.dart';
import 'package:test_flutter/core/models/daily_report.dart';
import 'package:test_flutter/core/services/child_service.dart';
import 'package:test_flutter/core/services/daily_report_service.dart';
import 'package:test_flutter/shared/util/date_display.dart';
import 'package:test_flutter/features/parent/screens/child_reports_screen.dart';

class MockChildService extends Mock implements ChildService {}

class MockDailyReportService extends Mock implements DailyReportService {}

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

DailyReport _report({String date = '2026-07-28', String text = '', List<String> images = const []}) =>
    DailyReport(
      id: 'report-$date',
      childId: 'child-1',
      teacherId: 'teacher-1',
      centerId: 'center-1',
      date: date,
      text: text,
      imagePaths: images,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: 'teacher-1',
      updatedBy: 'teacher-1',
    );

void main() {
  late MockChildService mockChildren;
  late MockDailyReportService mockReports;

  setUp(() {
    mockChildren = MockChildService();
    mockReports = MockDailyReportService();
  });

  Future<void> pumpScreen(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => Stream.value(_parent())),
            childServiceProvider.overrideWithValue(mockChildren),
            dailyReportServiceProvider.overrideWithValue(mockReports),
          ],
          child: const MaterialApp(home: Scaffold(body: ChildReportsScreen())),
        ),
      );

  testWidgets('shows a message when no children are linked', (tester) async {
    when(() => mockChildren.fetchForParent('parent-1')).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('No children linked to your account yet.'), findsOneWidget);
  });

  testWidgets('shows a message when the child has no reports', (tester) async {
    when(() => mockChildren.fetchForParent('parent-1')).thenAnswer((_) async => [_child()]);
    when(() => mockReports.fetchForChild('child-1')).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('No reports yet.'), findsOneWidget);
  });

  testWidgets('shows the report feed with date and text', (tester) async {
    when(() => mockChildren.fetchForParent('parent-1')).thenAnswer((_) async => [_child()]);
    when(() => mockReports.fetchForChild('child-1')).thenAnswer(
      (_) async => [
        _report(date: '2026-07-28', text: 'Painted a rainbow.'),
        _report(date: '2026-07-27', text: 'Nap was good.'),
      ],
    );

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text(isoWithWeekday('2026-07-28')), findsOneWidget);
    expect(find.text('Painted a rainbow.'), findsOneWidget);
    expect(find.text(isoWithWeekday('2026-07-27')), findsOneWidget);
    expect(find.text('Nap was good.'), findsOneWidget);
  });

  testWidgets('renders photo thumbnails for a report with images', (tester) async {
    when(() => mockChildren.fetchForParent('parent-1')).thenAnswer((_) async => [_child()]);
    when(() => mockReports.fetchForChild('child-1')).thenAnswer(
      (_) async => [
        _report(date: '2026-07-28', text: 'Fun day', images: ['child-1/2026-07-28/1.jpg']),
      ],
    );
    // Never resolves so no real network image decode happens in tests.
    when(() => mockReports.getSignedReportImageUrl(any()))
        .thenAnswer((_) => Completer<String>().future);

    await pumpScreen(tester);
    // Several finite pumps (not pumpAndSettle): walk the nested futures
    // (user -> children -> reports) to completion, but stop short of the
    // thumbnail's never-resolving signed URL, whose spinner would make
    // pumpAndSettle hang forever.
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }

    expect(find.text('Fun day'), findsOneWidget);
    // A loading spinner inside the thumbnail slot while the URL is pending.
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });
}
