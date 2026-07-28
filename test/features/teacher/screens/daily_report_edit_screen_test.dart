import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/auth/auth_service.dart';
import 'package:test_flutter/core/models/app_user.dart';
import 'package:test_flutter/core/models/child.dart';
import 'package:test_flutter/core/models/daily_report.dart';
import 'package:test_flutter/core/services/daily_report_service.dart';
import 'package:test_flutter/core/services/photo_capture_service.dart';
import 'package:test_flutter/features/teacher/screens/daily_report_edit_screen.dart';

class MockDailyReportService extends Mock implements DailyReportService {}

class MockPhotoCaptureService extends Mock implements PhotoCaptureService {}

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

DailyReport _report({String text = 'Existing note', List<String> images = const []}) => DailyReport(
  id: 'report-1',
  childId: 'child-1',
  teacherId: 'teacher-1',
  centerId: 'center-1',
  date: '2026-07-28',
  text: text,
  imagePaths: images,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'teacher-1',
  updatedBy: 'teacher-1',
);

void main() {
  setUpAll(() {
    registerFallbackValue(XFile(''));
  });

  late MockDailyReportService mockReports;
  late MockPhotoCaptureService mockPhotoCapture;

  setUp(() {
    mockReports = MockDailyReportService();
    mockPhotoCapture = MockPhotoCaptureService();
  });

  Future<void> pumpScreen(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => Stream.value(_teacher())),
            dailyReportServiceProvider.overrideWithValue(mockReports),
            photoCaptureServiceProvider.overrideWithValue(mockPhotoCapture),
          ],
          child: MaterialApp(home: DailyReportEditScreen(child: _child())),
        ),
      );

  testWidgets('pre-fills the existing report text', (tester) async {
    when(() => mockReports.fetchForChildAndDate('child-1', any()))
        .thenAnswer((_) async => _report(text: 'Painted today'));

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Painted today'), findsOneWidget);
  });

  testWidgets('shows an empty form when there is no report yet', (tester) async {
    when(() => mockReports.fetchForChildAndDate('child-1', any()))
        .thenAnswer((_) async => null);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('No photos yet.'), findsOneWidget);
  });

  testWidgets('saving a new report inserts with the entered text', (tester) async {
    when(() => mockReports.fetchForChildAndDate('child-1', any()))
        .thenAnswer((_) async => null);
    when(() => mockReports.saveReport(
          childId: any(named: 'childId'),
          teacherId: any(named: 'teacherId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          text: any(named: 'text'),
          imagePaths: any(named: 'imagePaths'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
        )).thenAnswer((_) async => _report());

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Great day!');
    await tester.tap(find.text('Save report'));
    await tester.pumpAndSettle();

    verify(() => mockReports.saveReport(
          childId: 'child-1',
          teacherId: 'teacher-1',
          centerId: 'center-1',
          date: any(named: 'date'),
          text: 'Great day!',
          imagePaths: const [],
          actorUid: 'teacher-1',
          existingId: null,
        )).called(1);
  });

  testWidgets('editing an existing report updates with its id', (tester) async {
    when(() => mockReports.fetchForChildAndDate('child-1', any()))
        .thenAnswer((_) async => _report(text: 'Old'));
    when(() => mockReports.saveReport(
          childId: any(named: 'childId'),
          teacherId: any(named: 'teacherId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          text: any(named: 'text'),
          imagePaths: any(named: 'imagePaths'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
        )).thenAnswer((_) async => _report());

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Updated');
    await tester.tap(find.text('Save report'));
    await tester.pumpAndSettle();

    verify(() => mockReports.saveReport(
          childId: 'child-1',
          teacherId: 'teacher-1',
          centerId: 'center-1',
          date: any(named: 'date'),
          text: 'Updated',
          imagePaths: const [],
          actorUid: 'teacher-1',
          existingId: 'report-1',
        )).called(1);
  });

  testWidgets('adding a photo uploads it and includes its path on save', (tester) async {
    when(() => mockReports.fetchForChildAndDate('child-1', any()))
        .thenAnswer((_) async => null);
    when(() => mockPhotoCapture.captureFromCamera()).thenAnswer((_) async => XFile(''));
    when(() => mockReports.uploadReportImage(
          childId: any(named: 'childId'),
          date: any(named: 'date'),
          photo: any(named: 'photo'),
        )).thenAnswer((_) async => 'child-1/2026-07-28/1.jpg');
    // The thumbnail's signed URL never resolves so it can't attempt a real
    // network image decode in the test environment.
    when(() => mockReports.getSignedReportImageUrl(any()))
        .thenAnswer((_) => Completer<String>().future);
    when(() => mockReports.saveReport(
          childId: any(named: 'childId'),
          teacherId: any(named: 'teacherId'),
          centerId: any(named: 'centerId'),
          date: any(named: 'date'),
          text: any(named: 'text'),
          imagePaths: any(named: 'imagePaths'),
          actorUid: any(named: 'actorUid'),
          existingId: any(named: 'existingId'),
        )).thenAnswer((_) async => _report());

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take photo'));
    await tester.pump();

    verify(() => mockReports.uploadReportImage(
          childId: 'child-1',
          date: any(named: 'date'),
          photo: any(named: 'photo'),
        )).called(1);

    await tester.tap(find.text('Save report'));
    await tester.pump();

    verify(() => mockReports.saveReport(
          childId: 'child-1',
          teacherId: 'teacher-1',
          centerId: 'center-1',
          date: any(named: 'date'),
          text: '',
          imagePaths: const ['child-1/2026-07-28/1.jpg'],
          actorUid: 'teacher-1',
          existingId: null,
        )).called(1);
  });
}
