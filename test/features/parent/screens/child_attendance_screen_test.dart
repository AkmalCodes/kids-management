import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/auth/auth_controller.dart';
import 'package:test_flutter/core/models/app_user.dart';
import 'package:test_flutter/core/models/attendance.dart';
import 'package:test_flutter/core/models/child.dart';
import 'package:test_flutter/core/controllers/attendance_controller.dart';
import 'package:test_flutter/core/controllers/child_controller.dart';
import 'package:test_flutter/shared/util/date_display.dart';
import 'package:test_flutter/features/parent/screens/attendance_detail_screen.dart';
import 'package:test_flutter/features/parent/screens/child_attendance_screen.dart';
import 'package:test_flutter/shared/widgets/signed_photo_thumbnail.dart';

class MockChildController extends Mock implements ChildController {}

class MockAttendanceController extends Mock implements AttendanceController {}

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

Attendance _record(String date, AttendanceStatus status) => Attendance(
  id: 'att-$date',
  childId: 'child-1',
  centerId: 'center-1',
  date: date,
  status: status,
  notes: '',
  photoPath: null,
  belongingsPhotoPath: null,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'teacher-1',
  updatedBy: 'teacher-1',
);

void main() {
  late MockChildController mockChildren;
  late MockAttendanceController mockAttendance;

  setUp(() {
    mockChildren = MockChildController();
    mockAttendance = MockAttendanceController();
  });

  Future<void> pumpScreen(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => Stream.value(_parent())),
            childControllerProvider.overrideWithValue(mockChildren),
            attendanceControllerProvider.overrideWithValue(mockAttendance),
          ],
          child: const MaterialApp(home: Scaffold(body: ChildAttendanceScreen())),
        ),
      );

  testWidgets('shows a message when no children are linked', (tester) async {
    when(() => mockChildren.fetchForParent('parent-1')).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('No children linked to your account yet.'), findsOneWidget);
  });

  testWidgets('shows attendance history for the linked child', (tester) async {
    when(() => mockChildren.fetchForParent('parent-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForChild('child-1')).thenAnswer(
      (_) async => [_record('2026-07-17', AttendanceStatus.present)],
    );

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text(isoWithWeekday('2026-07-17')), findsOneWidget);
    expect(find.text('Present'), findsOneWidget);
  });

  testWidgets('shows photo thumbnails when a record has attached photos', (tester) async {
    final record = Attendance(
      id: 'att-2026-07-17',
      childId: 'child-1',
      centerId: 'center-1',
      date: '2026-07-17',
      status: AttendanceStatus.present,
      notes: '',
      photoPath: 'child-1/2026-07-17.jpg',
      belongingsPhotoPath: 'child-1/2026-07-17-belongings.jpg',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: 'teacher-1',
      updatedBy: 'teacher-1',
    );
    when(() => mockChildren.fetchForParent('parent-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForChild('child-1')).thenAnswer((_) async => [record]);
    when(() => mockAttendance.getSignedPhotoUrl(any()))
        .thenAnswer((_) async => 'https://example.supabase.co/signed/photo.jpg');

    await pumpScreen(tester);
    // Several single pumps (not pumpAndSettle) to walk through this
    // screen's nested FutureBuilders (user stream -> children -> per-child
    // attendance) one resolution at a time, stopping short of letting the
    // thumbnails' own signed-URL futures resolve -- once those resolve,
    // CircleAvatar would attempt a real network image decode in the test
    // environment and throw.
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.byType(SignedPhotoThumbnail), findsNWidgets(2));
  });

  testWidgets('tapping a record card opens the detail view', (tester) async {
    final record = Attendance(
      id: 'att-2026-07-17',
      childId: 'child-1',
      centerId: 'center-1',
      date: '2026-07-17',
      status: AttendanceStatus.present,
      notes: '',
      photoPath: 'child-1/2026-07-17.jpg',
      belongingsPhotoPath: null,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: 'teacher-1',
      updatedBy: 'teacher-1',
    );
    when(() => mockChildren.fetchForParent('parent-1'))
        .thenAnswer((_) async => [_child()]);
    when(() => mockAttendance.fetchForChild('child-1')).thenAnswer((_) async => [record]);
    // Never resolves so the large photo never triggers a real network decode.
    when(() => mockAttendance.getSignedPhotoUrl(any()))
        .thenAnswer((_) => Completer<String>().future);
    // Tall surface so both photo sections fit in the detail ListView's
    // viewport (otherwise the belongings section stays lazily unbuilt).
    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(tester);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byType(Card).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AttendanceDetailScreen), findsOneWidget);
    expect(find.text('Check-in photo'), findsOneWidget);
    expect(find.text('Belongings photo'), findsOneWidget);
  });
}
