import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kawankecil/core/auth/auth_controller.dart';
import 'package:kawankecil/core/models/app_user.dart';
import 'package:kawankecil/core/models/lesson_plan.dart';
import 'package:kawankecil/core/models/schedule.dart';
import 'package:kawankecil/core/controllers/lesson_plan_controller.dart';
import 'package:kawankecil/core/controllers/schedule_controller.dart';
import 'package:kawankecil/core/controllers/subject_controller.dart';
import 'package:kawankecil/core/models/subject.dart';
import 'package:kawankecil/shared/widgets/schedule_event_sheet.dart';
import 'package:kawankecil/features/shared_lessons/lesson_plan_view_screen.dart';
import 'package:kawankecil/shared/widgets/day_timetable.dart';
import 'package:kawankecil/shared/widgets/schedule_agenda_view.dart';

// anchorDate is injected everywhere so tests don't depend on the real
// current date/time. It is "now": Friday 17 July 2026, 10:12. Its week is
// Mon 13 – Sun 19 July.
final _anchor = DateTime(2026, 7, 17, 10, 12);

ScheduleEntry _entry(
  String id,
  String day,
  String start,
  String end,
  String label, {
  String recurrence = 'weekly',
  DateTime? anchorDate,
  String color = '26A69A',
}) =>
    ScheduleEntry(
      id: id,
      type: 'teacher',
      refId: 'teacher-1',
      centerId: 'center-1',
      day: day,
      startTime: start,
      endTime: end,
      label: label,
      color: color,
      recurrence: recurrence,
      anchorDate: anchorDate,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: 'teacher-1',
      updatedBy: 'teacher-1',
    );

final _entries = [
  _entry('entry-1', 'Monday', '08:00', '09:00', 'Art'),
  _entry('entry-2', 'Wednesday', '10:00', '11:00', 'Music'),
  _entry('entry-3', 'Friday', '08:00', '08:30', 'Morning circle'),
  _entry('entry-4', 'Friday', '10:00', '10:30', 'Snack time'),
  _entry('entry-5', 'Friday', '15:00', '15:45', 'Outdoor play'),
];

Widget _wrap(Widget child) =>
    ProviderScope(child: MaterialApp(home: Scaffold(body: child)));

class MockScheduleController extends Mock implements ScheduleController {}

class MockLessonPlanController extends Mock implements LessonPlanController {}

class MockSubjectController extends Mock implements SubjectController {}

AppUser _user(String id, {String role = 'teacher'}) => AppUser(
      id: id,
      role: role,
      name: 'Teacher',
      phone: '',
      centerId: 'center-1',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: 'director-1',
      updatedBy: 'director-1',
    );

// An editable agenda (a teacher's own schedule) with the controllers mocked.
Future<void> _pumpEditable(
  WidgetTester tester, {
  required MockScheduleController service,
  List<ScheduleEntry>? entries,
  String viewerId = 'teacher-1',
  String? centerId = 'center-1',
}) =>
    tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_user(viewerId))),
        scheduleControllerProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ScheduleAgendaView(
            entries: entries ?? _entries,
            anchorDate: _anchor,
            type: 'teacher',
            refId: 'teacher-1',
            centerId: centerId,
            editable: true,
          ),
        ),
      ),
    ));

void main() {
  testWidgets('header shows the month and a week strip with the selected day',
      (tester) async {
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: const [], anchorDate: _anchor)));

    expect(find.text('July 2026'), findsOneWidget);
    for (var d = 13; d <= 19; d++) {
      expect(find.byKey(Key('week-day-2026-07-$d')), findsOneWidget);
    }
    expect(find.byTooltip('Pick a date'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    // Today (Friday) is selected, so its agenda heading is shown.
    expect(find.text('Friday · No activities'), findsOneWidget);
    expect(find.text('No activities on this day.'), findsOneWidget);
  });

  testWidgets('agenda lists only the selected day, sorted by start time', (tester) async {
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: _entries, anchorDate: _anchor)));

    expect(find.text('Friday · 3 activities'), findsOneWidget);
    expect(find.text('Morning circle'), findsOneWidget);
    expect(find.text('Snack time'), findsOneWidget);
    expect(find.text('Outdoor play'), findsOneWidget);
    expect(find.text('Art'), findsNothing); // Monday's
    final y1 = tester.getTopLeft(find.text('Morning circle')).dy;
    final y2 = tester.getTopLeft(find.text('Outdoor play')).dy;
    expect(y1, lessThan(y2));
  });

  testWidgets('tapping a day in the strip switches the agenda to that day', (tester) async {
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: _entries, anchorDate: _anchor)));

    await tester.tap(find.byKey(const Key('week-day-2026-07-13')));
    await tester.pumpAndSettle();

    expect(find.text('Monday · 1 activity'), findsOneWidget);
    expect(find.text('Art'), findsOneWidget);
    expect(find.text('Snack time'), findsNothing);
  });

  testWidgets('swiping the strip changes week; Today jumps back', (tester) async {
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: const [], anchorDate: _anchor)));

    await tester.fling(find.byKey(const Key('week-strip')), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    // Next week; the same weekday (Friday the 24th) stays selected.
    expect(find.byKey(const Key('week-day-2026-07-20')), findsOneWidget);
    expect(find.byKey(const Key('week-day-2026-07-13')), findsNothing);

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('week-day-2026-07-13')), findsOneWidget);
  });

  testWidgets('today: past events fade, the current one is marked Now, a now line shows',
      (tester) async {
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: _entries, anchorDate: _anchor)));

    // 10:12 is inside Snack time (10:00–10:30).
    expect(find.text('Now'), findsOneWidget);
    expect(find.byKey(const Key('now-line')), findsOneWidget);
    // Morning circle (08:00–08:30) is over.
    final faded = tester.widget<Opacity>(find.byKey(const Key('agenda-row-entry-3')));
    expect(faded.opacity, lessThan(1));
    final current = tester.widget<Opacity>(find.byKey(const Key('agenda-row-entry-4')));
    expect(current.opacity, 1);
  });

  testWidgets('another day has no Now marker or now line', (tester) async {
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: _entries, anchorDate: _anchor)));
    await tester.tap(find.byKey(const Key('week-day-2026-07-15')));
    await tester.pumpAndSettle();

    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Now'), findsNothing);
    expect(find.byKey(const Key('now-line')), findsNothing);
  });

  testWidgets("event card's colour bar follows the entry's saved colour", (tester) async {
    final entries = [_entry('e1', 'Friday', '08:00', '09:00', 'Art', color: 'D81B60')];
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: entries, anchorDate: _anchor)));

    final bar = tester.widget<Container>(find.byKey(const Key('event-bar-e1')));
    expect((bar.decoration as BoxDecoration).color, const Color(0xFFD81B60));
  });

  testWidgets('the toggle swaps the agenda for the hour grid and back', (tester) async {
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: _entries, anchorDate: _anchor)));
    expect(find.byType(DayTimetable), findsNothing);

    await tester.tap(find.byTooltip('Timeline view'));
    await tester.pumpAndSettle();
    expect(find.byType(DayTimetable), findsOneWidget);
    expect(find.byKey(const Key('timetable-now-line')), findsOneWidget); // today
    // Same screen: the strip and heading are still there.
    expect(find.text('Friday · 3 activities'), findsOneWidget);

    await tester.tap(find.byTooltip('List view'));
    await tester.pumpAndSettle();
    expect(find.byType(DayTimetable), findsNothing);
    expect(find.text('Morning circle'), findsOneWidget);
  });

  testWidgets('read-only: tapping an event opens its summary without actions', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [currentUserProvider.overrideWith((ref) => Stream.value(_user('parent-1')))],
      child: MaterialApp(
        home: Scaffold(body: ScheduleAgendaView(entries: _entries, anchorDate: _anchor)),
      ),
    ));

    await tester.tap(find.text('Outdoor play'));
    await tester.pumpAndSettle();

    expect(find.text('15:00 – 15:45'), findsOneWidget);
    expect(find.text('Every Friday'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('a once entry shows only on its anchor date', (tester) async {
    final onceEntry = _entry('once-1', 'Monday', '10:00', '11:00', 'One-off',
        recurrence: 'once', anchorDate: DateTime(2026, 7, 17));
    // Its day field ('Monday') would match Monday the 13th under a weekly
    // rule; a correct 'once' rule must not show it there.
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: [onceEntry], anchorDate: _anchor)));
    expect(find.text('One-off'), findsOneWidget);

    await tester.tap(find.byKey(const Key('week-day-2026-07-13')));
    await tester.pumpAndSettle();
    expect(find.text('One-off'), findsNothing);
  });

  testWidgets('a daily entry shows on weekdays, not weekends', (tester) async {
    final entries = [
      _entry('d1', 'Monday', '09:00', '10:00', 'Daily Standup', recurrence: 'daily'),
    ];
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: entries, anchorDate: _anchor)));
    expect(find.text('Daily Standup'), findsOneWidget); // Friday

    await tester.tap(find.byKey(const Key('week-day-2026-07-18')));
    await tester.pumpAndSettle();
    expect(find.text('Daily Standup'), findsNothing); // Saturday
  });

  testWidgets('no Add button when read-only', (tester) async {
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: _entries, anchorDate: _anchor)));
    expect(find.byTooltip('Add event'), findsNothing);
  });

  testWidgets('+ opens the create form; saving creates the event and lists it', (tester) async {
    final service = MockScheduleController();
    when(() => service.createEntry(
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
          lessonPlanId: any(named: 'lessonPlanId'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => _entry('new-1', 'Friday', '11:00', '12:00', 'Music'));

    await _pumpEditable(tester, service: service);
    await tester.tap(find.byTooltip('Add event'));
    await tester.pumpAndSettle();

    expect(find.text('New event'), findsOneWidget);
    // Today at 10:12: the form starts at the next hour.
    expect(find.text('11:00'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('event-name')), 'Music');
    await tester.tap(find.text('Add event'));
    await tester.pumpAndSettle();

    verify(() => service.createEntry(
          type: 'teacher',
          refId: 'teacher-1',
          centerId: 'center-1',
          day: 'Friday',
          startTime: '11:00',
          endTime: '12:00',
          label: 'Music',
          color: any(named: 'color'),
          recurrence: 'weekly',
          anchorDate: DateTime(2026, 7, 17),
          lessonPlanId: null,
          actorUid: 'teacher-1',
        )).called(1);
    expect(find.text('Music'), findsOneWidget); // shown without a re-fetch
    expect(find.text('Friday · 4 activities'), findsOneWidget);
  });

  testWidgets('tapping an empty hour on the timeline opens the form at that hour',
      (tester) async {
    await _pumpEditable(tester, service: MockScheduleController(), entries: const []);
    await tester.tap(find.byTooltip('Timeline view'));
    await tester.pumpAndSettle();

    final grid = tester.getTopLeft(find.byKey(const Key('day-timetable-grid')));
    // Rows are 56px from 07:00: y=6.5 rows down is inside the 13:00 hour.
    await tester.tapAt(grid + const Offset(10, 56 * 6.5));
    await tester.pumpAndSettle();

    expect(find.text('New event'), findsOneWidget);
    // Scoped to the sheet: the grid behind it has "13:00" hour labels too.
    final inSheet = find.byType(ScheduleEventSheet);
    expect(find.descendant(of: inSheet, matching: find.text('13:00')), findsOneWidget);
    expect(find.descendant(of: inSheet, matching: find.text('14:00')), findsOneWidget);
  });

  testWidgets('Edit in the sheet saves through updateEntry and updates the list',
      (tester) async {
    final service = MockScheduleController();
    when(() => service.updateEntry(
          id: any(named: 'id'),
          day: any(named: 'day'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          label: any(named: 'label'),
          color: any(named: 'color'),
          recurrence: any(named: 'recurrence'),
          anchorDate: any(named: 'anchorDate'),
          lessonPlanId: any(named: 'lessonPlanId'),
          actorUid: any(named: 'actorUid'),
        )).thenAnswer((_) async => _entry('entry-5', 'Friday', '15:00', '15:45', 'Garden time'));

    await _pumpEditable(tester, service: service);
    await tester.tap(find.text('Outdoor play'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('event-name')), 'Garden time');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(() => service.updateEntry(
          id: 'entry-5',
          day: 'Friday',
          startTime: '15:00',
          endTime: '15:45',
          label: 'Garden time',
          color: any(named: 'color'),
          recurrence: 'weekly',
          anchorDate: any(named: 'anchorDate'),
          lessonPlanId: null,
          actorUid: 'teacher-1',
        )).called(1);
    expect(find.text('Garden time'), findsOneWidget);
    expect(find.text('Outdoor play'), findsNothing);
  });

  testWidgets('Delete (confirmed) removes the event', (tester) async {
    final service = MockScheduleController();
    when(() => service.deleteEntry('entry-5')).thenAnswer((_) async {});

    await _pumpEditable(tester, service: service);
    await tester.tap(find.text('Outdoor play'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    verify(() => service.deleteEntry('entry-5')).called(1);
    expect(find.text('Outdoor play'), findsNothing);
    expect(find.text('Friday · 2 activities'), findsOneWidget);
  });

  testWidgets("someone else's event: no actions, the sheet says why", (tester) async {
    await _pumpEditable(tester, service: MockScheduleController(), viewerId: 'teacher-2');
    await tester.tap(find.text('Outdoor play'));
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsNothing);
    expect(find.text('Only the creator or a director can edit this event.'), findsOneWidget);
  });

  testWidgets('missing centerId: + explains instead of opening the form', (tester) async {
    await _pumpEditable(tester, service: MockScheduleController(), centerId: null);
    await tester.tap(find.byTooltip('Add event'));
    await tester.pumpAndSettle();

    expect(find.text('New event'), findsNothing);
    expect(
      find.text("Can't add an event: your account has no center assigned. Contact your director."),
      findsOneWidget,
    );
  });

  testWidgets('class schedule: subject shows on the card; the sheet opens the plan',
      (tester) async {
    final plans = MockLessonPlanController();
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
    when(() => plans.fetchClassPlanSubjects(any())).thenAnswer(
      (_) async => [const PlanSubject(id: 'lp-1', title: 'Watercolours', subject: 'Arts')],
    );
    when(() => plans.fetchApprovedForClass(any())).thenAnswer((_) async => [plan]);
    // LessonPlanViewScreen looks the subject up itself.
    final subjects = MockSubjectController();
    when(() => subjects.fetchAll()).thenAnswer((_) async => [
          Subject(
            id: 'sub-1',
            centerId: 'center-1',
            name: 'Arts',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            createdBy: 'director-1',
            updatedBy: 'director-1',
          ),
        ]);
    final entry = ScheduleEntry(
      id: 'ev-1',
      type: 'class',
      refId: 'class-1',
      centerId: 'center-1',
      day: 'Friday',
      startTime: '09:00',
      endTime: '10:00',
      label: 'Story time',
      color: '26A69A',
      recurrence: 'weekly',
      lessonPlanId: 'lp-1',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: 'teacher-1',
      updatedBy: 'teacher-1',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_user('parent-1', role: 'parent'))),
        lessonPlanControllerProvider.overrideWithValue(plans),
        subjectControllerProvider.overrideWithValue(subjects),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ScheduleAgendaView(
            entries: [entry],
            anchorDate: _anchor,
            type: 'class',
            refId: 'class-1',
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Arts'), findsOneWidget); // subject chip on the card
    await tester.tap(find.text('Story time'));
    await tester.pumpAndSettle();
    expect(find.text('Watercolours'), findsOneWidget);
    await tester.tap(find.byKey(const Key('event-sheet-plan')));
    await tester.pumpAndSettle();
    expect(find.byType(LessonPlanViewScreen), findsOneWidget);
    expect(find.text('Paint a rainbow'), findsOneWidget);
  });

  testWidgets('fits a 360px-wide phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final entries = [
      _entry('long', 'Friday', '09:00', '10:00', 'A very long activity name that keeps going'),
    ];
    await tester.pumpWidget(_wrap(ScheduleAgendaView(entries: entries, anchorDate: _anchor)));
    expect(tester.takeException(), isNull);
  });
}
