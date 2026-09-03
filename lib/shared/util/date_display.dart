// Small date-to-text helpers shared by the attendance/report screens so a
// weekday name is shown beside a date consistently. Deliberately does NOT
// touch birthdates -- those read fine as a plain date.

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

// DateTime.weekday is 1 (Monday) … 7 (Sunday).
String weekdayName(DateTime d) => _weekdayNames[d.weekday - 1];

// Prefix an ISO `yyyy-MM-dd` date string with its weekday, e.g.
// '2026-07-30' -> 'Thursday, 2026-07-30'. Returns the input unchanged if it
// can't be parsed (defensive; dates in this app are always ISO strings).
String isoWithWeekday(String isoDate) {
  final d = DateTime.tryParse(isoDate);
  if (d == null) return isoDate;
  return '${weekdayName(d)}, $isoDate';
}

// 24-hour `HH:mm` for a DateTime, e.g. 06:05 or 14:32. Hand-rolled on
// purpose: this project has no `intl` dependency and pulling one in for a
// single format string isn't worth it. Caller passes an already-localised
// DateTime (`.toLocal()`); this does no timezone conversion.
String hourMinute(DateTime d) {
  final h = d.hour.toString().padLeft(2, '0');
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
