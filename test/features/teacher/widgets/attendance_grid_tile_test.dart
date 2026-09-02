import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/core/models/attendance.dart';
import 'package:kids_management/core/models/child.dart';
import 'package:kids_management/features/teacher/widgets/attendance_grid_tile.dart';

Child _child({String name = 'Alice', String? avatarPath}) => Child(
  id: 'child-1',
  name: name,
  dob: DateTime(2022, 1, 1),
  centerId: 'center-1',
  className: 'Sunflower',
  teacherId: 'teacher-1',
  allergies: '',
  notes: '',
  avatarPath: avatarPath,
  enrolledAt: DateTime(2026),
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

Attendance _attendance(AttendanceStatus status) => Attendance(
  id: 'att-1',
  childId: 'child-1',
  centerId: 'center-1',
  date: '2026-09-01',
  status: status,
  notes: '',
  photoPath: null,
  belongingsPhotoPath: null,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'teacher-1',
  updatedBy: 'teacher-1',
);

Future<void> _pump(
  WidgetTester tester, {
  Attendance? attendance,
  VoidCallback? onTap,
  VoidCallback? onLongPress,
}) =>
    tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              // The tile is built for a GridView cell, which bounds its width.
              // Reproduce that here: unbounded width makes AspectRatio(1) fill
              // the viewport and overflow. ~84x108 matches a real cell on a
              // 400pt-wide phone at crossAxisCount 4, childAspectRatio 0.78.
              child: SizedBox(
                width: 84,
                height: 108,
                child: AttendanceGridTile(
                  child: _child(),
                  attendance: attendance,
                  onTap: onTap ?? () {},
                  onLongPress: onLongPress ?? () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('shows the child name', (tester) async {
    await _pump(tester);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('a present record shows the present badge', (tester) async {
    await _pump(tester, attendance: _attendance(AttendanceStatus.present));
    expect(find.byKey(const Key('status-badge-present')), findsOneWidget);
    expect(find.byKey(const Key('status-badge-absent')), findsNothing);
    expect(find.byKey(const Key('status-badge-unmarked')), findsNothing);
  });

  testWidgets('an absent record shows the absent badge', (tester) async {
    await _pump(tester, attendance: _attendance(AttendanceStatus.absent));
    expect(find.byKey(const Key('status-badge-absent')), findsOneWidget);
  });

  testWidgets('no record shows the unmarked badge', (tester) async {
    await _pump(tester, attendance: null);
    expect(find.byKey(const Key('status-badge-unmarked')), findsOneWidget);
  });

  testWidgets('late and excused fall back to the unmarked badge', (tester) async {
    // The UI can only ever set present or absent, so these are unreachable
    // from here. They render as unmarked rather than inventing an icon for a
    // state a teacher cannot produce.
    await _pump(tester, attendance: _attendance(AttendanceStatus.late));
    expect(find.byKey(const Key('status-badge-unmarked')), findsOneWidget);

    await _pump(tester, attendance: _attendance(AttendanceStatus.excused));
    expect(find.byKey(const Key('status-badge-unmarked')), findsOneWidget);
  });

  testWidgets('tap and long-press fire their callbacks', (tester) async {
    var taps = 0;
    var longPresses = 0;
    await _pump(tester, onTap: () => taps++, onLongPress: () => longPresses++);

    await tester.tap(find.byType(AttendanceGridTile));
    await tester.pump();
    expect(taps, 1);
    expect(longPresses, 0);

    await tester.longPress(find.byType(AttendanceGridTile));
    await tester.pump();
    expect(longPresses, 1);
    expect(taps, 1);
  });
}
