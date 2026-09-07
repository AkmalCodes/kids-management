import '../../core/models/schedule.dart';

const _weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

// The last calendar day of a month: day 0 of the next month. Gives 29 for
// February in a leap year, 28 otherwise -- so this doubles as the leap-year
// test (_lastDayOfMonth(y, 2) == 29).
int _lastDayOfMonth(int year, int month) => DateTime(year, month + 1, 0).day;

// The day-of-month an annual entry lands on in `year`. Normally the anchor's
// own day; the one exception is a 29-February anchor in a non-leap year,
// which falls back to the 28th. (No other date can be missing from a year.)
int _annualDayInYear(DateTime anchor, int year) {
  if (anchor.month == 2 && anchor.day == 29 && _lastDayOfMonth(year, 2) != 29) {
    return 28;
  }
  return anchor.day;
}

// Does this recurring entry have an occurrence on `date`? `date`'s time part
// is ignored. Every recurrence rule -- and all the leap-year handling --
// lives here; ScheduleAgendaView._entriesFor is the only caller.
bool scheduleEntryOccursOn(ScheduleEntry e, DateTime date) {
  switch (e.recurrence) {
    case 'daily':
      return date.weekday >= DateTime.monday && date.weekday <= DateTime.friday;
    case 'weekly':
      return _weekdayNames[date.weekday - 1] == e.day;
    case 'monthly':
      final anchor = e.anchorDate;
      if (anchor == null) return false;
      final target =
          anchor.day < _lastDayOfMonth(date.year, date.month)
              ? anchor.day
              : _lastDayOfMonth(date.year, date.month);
      return date.day == target;
    case 'annually':
      final anchor = e.anchorDate;
      if (anchor == null) return false;
      return date.month == anchor.month &&
          date.day == _annualDayInYear(anchor, date.year);
    default:
      return false;
  }
}
