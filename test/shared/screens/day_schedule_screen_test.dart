import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test_flutter/core/auth/auth_service.dart';
import 'package:test_flutter/core/models/app_user.dart';
import 'package:test_flutter/core/models/schedule.dart';
import 'package:test_flutter/core/services/schedule_service.dart';
import 'package:test_flutter/shared/screens/day_schedule_screen.dart';
import 'package:test_flutter/shared/widgets/day_timetable.dart';

class MockScheduleService extends Mock implements ScheduleService {}

AppUser _teacher(String id) => AppUser(
  id: id,
  role: 'teacher',
  name: 'Teacher',
  phone: '',
  centerId: 'center-1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  createdBy: 'director-1',
  updatedBy: 'director-1',
);

ScheduleEntry _entry({
  required String id,
  required String createdBy,
  String label = 'Art',
}) =>
    ScheduleEntry(
      id: id,
      type: 'teacher',
      refId: 'teacher-1',
      centerId: 'center-1',
      day: 'Monday',
      startTime: '08:00',
      endTime: '09:00',
      label: label,
      color: '26A69A',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: createdBy,
      updatedBy: createdBy,
    );

final _monday = DateTime(2026, 7, 13); // matches the fixture entries' 'Monday'

void main() {
  setUpAll(() {
    registerFallbackValue(_entry(id: 'fallback', createdBy: 'teacher-1'));
  });

  late MockScheduleService mockService;

  setUp(() {
    mockService = MockScheduleService();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<ScheduleEntry> entries,
    required String viewerId,
    bool editable = false,
    String? centerId = 'center-1',
  }) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => Stream.value(_teacher(viewerId))),
            scheduleServiceProvider.overrideWithValue(mockService),
          ],
          child: MaterialApp(
            home: DayScheduleScreen(
              date: _monday,
              entries: entries,
              type: 'teacher',
              refId: 'teacher-1',
              centerId: centerId,
              editable: editable,
            ),
          ),
        ),
      );

  testWidgets('read-only + no entries shows the empty message, no grid', (tester) async {
    await pumpScreen(tester, entries: const [], viewerId: 'teacher-1');
    expect(find.text('No events on this day.'), findsOneWidget);
    expect(find.byType(DayTimetable), findsNothing);
  });

  testWidgets('editable + no entries still shows the grid so a first event can be added',
      (tester) async {
    await pumpScreen(tester, entries: const [], viewerId: 'teacher-1', editable: true);
    expect(find.byType(DayTimetable), findsOneWidget);
  });

  testWidgets('editable shows a visible add button; read-only does not', (tester) async {
    await pumpScreen(tester, entries: const [], viewerId: 'teacher-1', editable: true);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('read-only shows no add button', (tester) async {
    await pumpScreen(tester, entries: const [], viewerId: 'teacher-1');
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets(
      'tapping the add button creates the entry and shows it immediately, '
      'with no extra fetch', (tester) async {
    when(() => mockService.createEntry(
          type: any(named: 'type'),
          refId: any(named: 'refId'),
          centerId: any(named: 'centerId'),
          day: any(named: 'day'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          label: any(named: 'label'),
          color: any(named: 'color'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => _entry(id: 'entry-1', createdBy: 'teacher-1', label: 'Music'));

    await pumpScreen(tester, entries: const [], viewerId: 'teacher-1', editable: true);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Create Event'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Music');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(() => mockService.createEntry(
          type: 'teacher',
          refId: 'teacher-1',
          centerId: 'center-1',
          day: 'Monday',
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          label: 'Music',
          color: any(named: 'color'),
          actorUid: 'teacher-1',
        )).called(1);
    // Shown from createEntry's returned row, not from a re-fetch.
    expect(find.text('Music'), findsOneWidget);
    verifyNever(() => mockService.fetchEntries(
          type: any(named: 'type'),
          refId: any(named: 'refId'),
        ));
  });

  testWidgets('editable: tapping empty space opens the add dialog and creates an entry',
      (tester) async {
    when(() => mockService.createEntry(
          type: any(named: 'type'),
          refId: any(named: 'refId'),
          centerId: any(named: 'centerId'),
          day: any(named: 'day'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          label: any(named: 'label'),
          color: any(named: 'color'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => _entry(id: 'entry-1', createdBy: 'teacher-1', label: 'Music'));

    await pumpScreen(tester, entries: const [], viewerId: 'teacher-1', editable: true);

    final gridTopLeft = tester.getTopLeft(find.byKey(const Key('day-timetable-grid')));
    await tester.tapAt(gridTopLeft + const Offset(10, 10)); // hour 7
    await tester.pumpAndSettle();

    expect(find.text('Create Event'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Music');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(() => mockService.createEntry(
          type: 'teacher',
          refId: 'teacher-1',
          centerId: 'center-1',
          day: 'Monday',
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          label: 'Music',
          color: any(named: 'color'),
          actorUid: 'teacher-1',
        )).called(1);
    expect(find.text('Music'), findsOneWidget);
  });

  testWidgets(
      'editable: tapping your own entry updates it in place, with no extra fetch',
      (tester) async {
    final entry = _entry(id: 'entry-1', createdBy: 'teacher-1');
    when(() => mockService.updateEntry(
          id: any(named: 'id'),
          day: any(named: 'day'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          label: any(named: 'label'),
          color: any(named: 'color'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer(
      (_) async => _entry(id: 'entry-1', createdBy: 'teacher-1', label: 'Art (updated)'),
    );

    await pumpScreen(tester, entries: [entry], viewerId: 'teacher-1', editable: true);

    final gridTopLeft = tester.getTopLeft(find.byKey(const Key('day-timetable-grid')));
    await tester.tapAt(gridTopLeft + const Offset(10, 70)); // inside the 08:00-09:00 block
    await tester.pumpAndSettle();

    expect(find.text('Edit Event'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Art (updated)');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(() => mockService.updateEntry(
          id: 'entry-1',
          day: 'Monday',
          startTime: '08:00',
          endTime: '09:00',
          label: 'Art (updated)',
          color: any(named: 'color'),
          actorUid: 'teacher-1',
        )).called(1);
    expect(find.text('Art (updated)'), findsOneWidget);
    expect(find.text('Art'), findsNothing);
    verifyNever(() => mockService.fetchEntries(
          type: any(named: 'type'),
          refId: any(named: 'refId'),
        ));
  });

  testWidgets('editable: deleting an entry removes it from the list, with no extra fetch',
      (tester) async {
    final entry = _entry(id: 'entry-1', createdBy: 'teacher-1');
    when(() => mockService.deleteEntry('entry-1')).thenAnswer((_) async {});

    await pumpScreen(tester, entries: [entry], viewerId: 'teacher-1', editable: true);

    final gridTopLeft = tester.getTopLeft(find.byKey(const Key('day-timetable-grid')));
    await tester.tapAt(gridTopLeft + const Offset(10, 70));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    verify(() => mockService.deleteEntry('entry-1')).called(1);
    expect(find.text('Art'), findsNothing);
    verifyNever(() => mockService.fetchEntries(
          type: any(named: 'type'),
          refId: any(named: 'refId'),
        ));
  });

  testWidgets('editable: tapping someone else\'s entry does not open an edit dialog',
      (tester) async {
    final entry = _entry(id: 'entry-1', createdBy: 'teacher-2');
    await pumpScreen(tester, entries: [entry], viewerId: 'teacher-1', editable: true);

    final gridTopLeft = tester.getTopLeft(find.byKey(const Key('day-timetable-grid')));
    await tester.tapAt(gridTopLeft + const Offset(10, 70));
    await tester.pumpAndSettle();

    expect(find.text('Edit Event'), findsNothing);
    expect(find.text('Only the creator or a director can edit this event.'), findsOneWidget);
    verifyNever(() => mockService.updateEntry(
          id: any(named: 'id'),
          day: any(named: 'day'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          label: any(named: 'label'),
          color: any(named: 'color'),
          actorUid: any(named: 'actorUid'),
        ));
  });

  testWidgets('missing centerId shows an error instead of silently doing nothing',
      (tester) async {
    await pumpScreen(
      tester,
      entries: const [],
      viewerId: 'teacher-1',
      editable: true,
      centerId: null,
    );

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Create Event'), findsNothing);
    expect(
      find.text("Can't add an event: your account has no center assigned. Contact your director."),
      findsOneWidget,
    );
    verifyNever(() => mockService.createEntry(
          type: any(named: 'type'),
          refId: any(named: 'refId'),
          centerId: any(named: 'centerId'),
          day: any(named: 'day'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          label: any(named: 'label'),
          color: any(named: 'color'),
          actorUid: any(named: 'actorUid'),
        ));
  });
}
