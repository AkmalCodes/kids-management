import '../../core/models/schedule.dart';

const _weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

// Does this entry have an occurrence on `date`? Time part of `date` is
// ignored. Three recurrences: 'once' (only on anchorDate), 'daily' (Mon-Fri),
// 'weekly' (the entry's `day`). ScheduleAgendaView._entriesFor is the only
// caller.
bool scheduleEntryOccursOn(ScheduleEntry e, DateTime date) {
  switch (e.recurrence) {
    case 'once':
      final a = e.anchorDate;
      return a != null &&
          a.year == date.year && a.month == date.month && a.day == date.day;
    case 'daily':
      return date.weekday >= DateTime.monday && date.weekday <= DateTime.friday;
    case 'weekly':
      return _weekdayNames[date.weekday - 1] == e.day;
    default:
      return false;
  }
}
