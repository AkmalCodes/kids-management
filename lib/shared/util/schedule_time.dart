// Small helpers for the "HH:mm" strings schedule entries store.

int _minutes(String hhmm) => int.parse(hhmm.substring(0, 2)) * 60 + int.parse(hhmm.substring(3, 5));

// "30 min", "1 hr", "1 hr 15 min" between two "HH:mm" times; '' when the
// end isn't after the start.
String scheduleDurationLabel(String start, String end) {
  final total = _minutes(end) - _minutes(start);
  if (total <= 0) return '';
  final h = total ~/ 60, rest = total % 60;
  if (h == 0) return '$rest min';
  return rest == 0 ? '$h hr' : '$h hr $rest min';
}
