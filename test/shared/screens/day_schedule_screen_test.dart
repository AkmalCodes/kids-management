import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kawankecil/core/auth/auth_controller.dart';
import 'package:kawankecil/core/models/app_user.dart';
import 'package:kawankecil/core/models/lesson_plan.dart';
import 'package:kawankecil/core/models/schedule.dart';
import 'package:kawankecil/core/models/subject.dart';
import 'package:kawankecil/core/controllers/lesson_plan_controller.dart';
import 'package:kawankecil/core/controllers/schedule_controller.dart';
import 'package:kawankecil/core/controllers/subject_controller.dart';
import 'package:kawankecil/features/shared_lessons/lesson_plan_view_screen.dart';
import 'package:kawankecil/shared/screens/day_schedule_screen.dart';
import 'package:kawankecil/shared/widgets/day_timetable.dart';

class MockScheduleController extends Mock implements ScheduleController {}

class MockLessonPlanController extends Mock implements LessonPlanController {}

class MockSubjectController extends Mock implements SubjectController {}

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
  String recurrence = 'weekly',
  DateTime? anchorDate,
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
      recurrence: recurrence,
      anchorDate: anchorDate,
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

  late MockScheduleController mockService;

  setUp(() {
    mockService = MockScheduleController();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<ScheduleEntry> entries,
    required String viewerId,
    bool editable = false,
    String? centerId = 'center-1',
    DateTime? date,
  }) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => Stream.value(_teacher(viewerId))),
            scheduleControllerProvider.overrideWithValue(mockService),
          ],
          child: MaterialApp(
            home: DayScheduleScreen(
              date: date ?? _monday,
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
    expect(find.text('No activities on this day.'), findsOneWidget);
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

  testWidgets('a class event with an attached plan shows its subject and opens it',
      (tester) async {
    final mockPlans = MockLessonPlanController();
    final mockSubjects = MockSubjectController();
    final plan = LessonPlan(
      id: 'lp-1',
      teacherId: 'teacher-1',
      centerId: 'center-1',
      title: 'Watercolours',
      content: 'Paint a rainbow',
      subjectId: 'sub-1',
      classId: 'class-1',
      status: LessonPlanStatus.approved,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: 'teacher-1',
      updatedBy: 'teacher-1',
    );
    when(() => mockPlans.fetchApprovedForClass(any())).thenAnswer((_) async => [plan]);
    // The subject label now comes from the connected-role RPC.
    when(() => mockPlans.fetchClassPlanSubjects(any())).thenAnswer(
      (_) async => [const PlanSubject(id: 'lp-1', title: 'Watercolours', subject: 'Art')],
    );
    when(() => mockSubjects.fetchAll()).thenAnswer(
      (_) async => [
        Subject(
          id: 'sub-1',
          centerId: 'center-1',
          name: 'Art',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          createdBy: 'director-1',
          updatedBy: 'director-1',
        ),
      ],
    );

    final entry = ScheduleEntry(
      id: 'ev-1',
      type: 'class',
      refId: 'class-1',
      centerId: 'center-1',
      day: 'Monday',
      startTime: '08:00',
      endTime: '09:00',
      label: 'Story time',
      color: '26A69A',
      recurrence: 'weekly',
      lessonPlanId: 'lp-1',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: 'teacher-1',
      updatedBy: 'teacher-1',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(_teacher('parent-1'))),
          scheduleControllerProvider.overrideWithValue(mockService),
          lessonPlanControllerProvider.overrideWithValue(mockPlans),
          subjectControllerProvider.overrideWithValue(mockSubjects),
        ],
        child: MaterialApp(
          home: DayScheduleScreen(
            date: _monday,
            entries: [entry],
            type: 'class',
            refId: 'class-1',
            centerId: 'center-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The event shows the attached plan's subject.
    expect(find.text('Art'), findsOneWidget);
    // Tapping the event (read-only viewer) opens the details sheet, with the
    // attached plan but no Edit/Delete...
    await tester.tap(find.byKey(const Key('entry-block-ev-1')));
    await tester.pumpAndSettle();
    expect(find.text('Watercolours'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    // ...and the plan card opens the plan read-only.
    await tester.tap(find.byKey(const Key('event-sheet-plan')));
    await tester.pumpAndSettle();
    expect(find.byType(LessonPlanViewScreen), findsOneWidget);
    expect(find.text('Paint a rainbow'), findsOneWidget);
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
          recurrence: any(named: 'recurrence'),
          anchorDate: any(named: 'anchorDate'),
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
          recurrence: any(named: 'recurrence'),
          anchorDate: any(named: 'anchorDate'),
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
          recurrence: any(named: 'recurrence'),
          anchorDate: any(named: 'anchorDate'),
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
          recurrence: any(named: 'recurrence'),
          anchorDate: any(named: 'anchorDate'),
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
          recurrence: any(named: 'recurrence'),
          anchorDate: any(named: 'anchorDate'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer(
      (_) async => _entry(id: 'entry-1', createdBy: 'teacher-1', label: 'Art (updated)'),
    );

    await pumpScreen(tester, entries: [entry], viewerId: 'teacher-1', editable: true);

    final gridTopLeft = tester.getTopLeft(find.byKey(const Key('day-timetable-grid')));
    await tester.tapAt(gridTopLeft + const Offset(10, 70)); // inside the 08:00-09:00 block
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit')); // in the event sheet
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
          recurrence: any(named: 'recurrence'),
          anchorDate: any(named: 'anchorDate'),
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

    await tester.tap(find.text('Delete')); // in the event sheet
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete')); // confirm
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
          recurrence: any(named: 'recurrence'),
          anchorDate: any(named: 'anchorDate'),
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
          recurrence: any(named: 'recurrence'),
          anchorDate: any(named: 'anchorDate'),
          actorUid: any(named: 'actorUid'),
        ));
  });

  testWidgets('creating an event with Once recurrence passes once + screen date to createEntry',
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
          recurrence: any(named: 'recurrence'),
          anchorDate: any(named: 'anchorDate'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => _entry(id: 'entry-1', createdBy: 'teacher-1', label: 'One-off Event', recurrence: 'once', anchorDate: _monday));

    await pumpScreen(tester, entries: const [], viewerId: 'teacher-1', editable: true);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Create Event'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'One-off Event');
    // Change recurrence from Weekly to Once
    await tester.tap(find.text('Weekly'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Once'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(() => mockService.createEntry(
          type: 'teacher',
          refId: 'teacher-1',
          centerId: 'center-1',
          day: 'Monday',
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          label: 'One-off Event',
          color: any(named: 'color'),
          recurrence: 'once',
          anchorDate: _monday,
          actorUid: 'teacher-1',
        )).called(1);
  });

  testWidgets('editing a once entry preserves its original anchorDate, not the viewed date',
      (tester) async {
    // The anchor (31 Jan) must survive the edit untouched.
    final anchorDate = DateTime(2026, 1, 31);
    final entry = _entry(
      id: 'entry-1',
      createdBy: 'teacher-1',
      recurrence: 'once',
      anchorDate: anchorDate,
    );
    when(() => mockService.updateEntry(
          id: any(named: 'id'),
          day: any(named: 'day'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          label: any(named: 'label'),
          color: any(named: 'color'),
          recurrence: any(named: 'recurrence'),
          anchorDate: any(named: 'anchorDate'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer(
      (_) async => _entry(id: 'entry-1', createdBy: 'teacher-1', recurrence: 'once', anchorDate: anchorDate),
    );

    // Viewed on its anchor date: a once entry only occurs there.
    await pumpScreen(tester,
        entries: [entry], viewerId: 'teacher-1', editable: true, date: anchorDate);

    final gridTopLeft = tester.getTopLeft(find.byKey(const Key('day-timetable-grid')));
    await tester.tapAt(gridTopLeft + const Offset(10, 70)); // inside the 08:00-09:00 block
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit')); // in the event sheet
    await tester.pumpAndSettle();

    expect(find.text('Edit Event'), findsOneWidget);
    // Save without changing the dropdown
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(() => mockService.updateEntry(
          id: 'entry-1',
          day: 'Monday',
          startTime: '08:00',
          endTime: '09:00',
          label: 'Art',
          color: any(named: 'color'),
          recurrence: 'once',
          anchorDate: DateTime(2026, 1, 31),
          actorUid: 'teacher-1',
        )).called(1);
  });

  testWidgets('title shows the day; the week strip switches day in place', (tester) async {
    final entries = [
      _entry(id: 'mon', createdBy: 'teacher-1', label: 'Art'),
      ScheduleEntry(
        id: 'wed',
        type: 'teacher',
        refId: 'teacher-1',
        centerId: 'center-1',
        day: 'Wednesday',
        startTime: '10:00',
        endTime: '11:00',
        label: 'Music',
        color: '5C6BC0',
        recurrence: 'weekly',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        createdBy: 'teacher-1',
        updatedBy: 'teacher-1',
      ),
    ];
    await pumpScreen(tester, entries: entries, viewerId: 'teacher-1', editable: true);

    expect(find.text('Monday, 13 Jul'), findsOneWidget);
    expect(find.text('Art'), findsOneWidget);
    expect(find.text('Music'), findsNothing);

    await tester.tap(find.byKey(const Key('week-day-2026-07-15')));
    await tester.pumpAndSettle();

    expect(find.text('Wednesday, 15 Jul'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Art'), findsNothing);
  });

  testWidgets('the event sheet shows time, length and how it repeats', (tester) async {
    await pumpScreen(tester,
        entries: [_entry(id: 'entry-1', createdBy: 'teacher-1')],
        viewerId: 'teacher-1',
        editable: true);

    final gridTopLeft = tester.getTopLeft(find.byKey(const Key('day-timetable-grid')));
    await tester.tapAt(gridTopLeft + const Offset(10, 70));
    await tester.pumpAndSettle();

    expect(find.text('08:00 – 09:00'), findsWidgets); // sheet (and the block)
    expect(find.text('Monday, 13 Jul · 1 hr'), findsOneWidget);
    expect(find.text('Every Monday'), findsOneWidget);
    expect(find.text('Added by you'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('cancelling the delete confirmation keeps the event', (tester) async {
    await pumpScreen(tester,
        entries: [_entry(id: 'entry-1', createdBy: 'teacher-1')],
        viewerId: 'teacher-1',
        editable: true);

    final gridTopLeft = tester.getTopLeft(find.byKey(const Key('day-timetable-grid')));
    await tester.tapAt(gridTopLeft + const Offset(10, 70));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => mockService.deleteEntry(any()));
    expect(find.text('Art'), findsOneWidget);
  });

  testWidgets('addOnOpen opens the create dialog straight away', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(_teacher('teacher-1'))),
          scheduleControllerProvider.overrideWithValue(mockService),
        ],
        child: MaterialApp(
          home: DayScheduleScreen(
            date: _monday,
            entries: const [],
            type: 'teacher',
            refId: 'teacher-1',
            centerId: 'center-1',
            editable: true,
            addOnOpen: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Create Event'), findsOneWidget);
  });

  testWidgets('viewing today draws the now line', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => Stream.value(_teacher('teacher-1'))),
          scheduleControllerProvider.overrideWithValue(mockService),
        ],
        child: MaterialApp(
          home: DayScheduleScreen(
            date: _monday,
            entries: [_entry(id: 'entry-1', createdBy: 'teacher-1')],
            now: DateTime(2026, 7, 13, 10, 12),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('timetable-now-line')), findsOneWidget);
  });

  testWidgets('day view and event sheet fit a 360px-wide phone', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpScreen(tester,
        entries: [
          _entry(id: 'entry-1', createdBy: 'teacher-1', label: 'A very long activity name indeed'),
        ],
        viewerId: 'teacher-1',
        editable: true);
    expect(tester.takeException(), isNull);

    final gridTopLeft = tester.getTopLeft(find.byKey(const Key('day-timetable-grid')));
    await tester.tapAt(gridTopLeft + const Offset(10, 70));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Edit'), findsOneWidget);
  });
}
