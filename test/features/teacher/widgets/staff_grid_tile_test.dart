import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/core/models/app_user.dart';
import 'package:kids_management/features/teacher/widgets/staff_grid_tile.dart';

AppUser _teacher({String? avatarPath}) => AppUser(
  id: 't-1',
  role: 'teacher',
  name: 'Aisha Rahman',
  phone: '',
  centerId: 'center-1',
  avatarPath: avatarPath,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

Future<void> _pump(
  WidgetTester tester, {
  StaffClockState? clockState,
  VoidCallback? onTap,
}) =>
    tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 84,
              height: 117,
              child: StaffGridTile(
                teacher: _teacher(),
                clockState: clockState,
                onTap: onTap ?? () {},
              ),
            ),
          ),
        ),
      ),
    ));

void main() {
  testWidgets('uses a circular avatar (unlike the child tile)', (tester) async {
    await _pump(tester);
    expect(find.byType(CircleAvatar), findsOneWidget);
  });

  testWidgets('shows the short name label', (tester) async {
    await _pump(tester);
    expect(find.text('Aisha R.'), findsOneWidget);
  });

  testWidgets('each clock state renders its distinct badge icon', (tester) async {
    await _pump(tester, clockState: StaffClockState.notClockedIn);
    expect(find.byIcon(Icons.schedule), findsOneWidget);

    await _pump(tester, clockState: StaffClockState.working);
    expect(find.byIcon(Icons.access_time_filled), findsOneWidget);

    await _pump(tester, clockState: StaffClockState.done);
    expect(find.byIcon(Icons.logout), findsOneWidget);
  });

  testWidgets('no clockState renders no badge', (tester) async {
    await _pump(tester, clockState: null);
    expect(find.byIcon(Icons.schedule), findsNothing);
    expect(find.byIcon(Icons.access_time_filled), findsNothing);
    expect(find.byIcon(Icons.logout), findsNothing);
  });

  testWidgets('tap fires the callback', (tester) async {
    var taps = 0;
    await _pump(tester, onTap: () => taps++);
    await tester.tap(find.byType(StaffGridTile));
    await tester.pump();
    expect(taps, 1);
  });
}
