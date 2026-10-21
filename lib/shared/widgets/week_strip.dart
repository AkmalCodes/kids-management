import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

// Mon..Sun day picker from screen design SA (Figma "Screen designs"), shared
// by the Schedule tab's agenda (SA1) and the day timeline (SA2).
//
// Seven equal cells, Mon..Sun. The selected day is a filled dark-rose tile;
// today (when not selected) gets its number in pink. A horizontal swipe
// anywhere on the strip moves a week.
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    super.key,
    required this.days,
    required this.selected,
    required this.today,
    required this.dotColorsFor,
    required this.onSelect,
    required this.onSwipe,
  });

  final List<DateTime> days;
  final DateTime selected;
  final DateTime today;
  final List<Color> Function(DateTime day) dotColorsFor;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<int> onSwipe;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  // Mon..Sun of the week containing `day` (DateTime.weekday: Monday = 1).
  // Built with the DateTime constructor, not Duration, so DST can't skew it.
  static List<DateTime> weekOf(DateTime day) {
    final monday = DateTime(day.year, day.month, day.day - (day.weekday - 1));
    return [for (var i = 0; i < 7; i++) DateTime(monday.year, monday.month, monday.day + i)];
  }

  static String _key(DateTime d) =>
      'week-day-${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('week-strip'),
      // Fling left = later week, right = earlier. Velocity, not distance, so
      // a short quick swipe works and a slow drag doesn't trigger by accident.
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -200) onSwipe(1);
        if (v > 200) onSwipe(-1);
      },
      child: Row(
        children: [
          for (final d in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _DayCell(
                  key: Key(_key(d)),
                  letter: _letters[d.weekday - 1],
                  day: d.day,
                  selected: d.year == selected.year &&
                      d.month == selected.month &&
                      d.day == selected.day,
                  isToday: d.year == today.year && d.month == today.month && d.day == today.day,
                  dots: dotColorsFor(d),
                  onTap: () => onSelect(d),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    super.key,
    required this.letter,
    required this.day,
    required this.selected,
    required this.isToday,
    required this.dots,
    required this.onTap,
  });

  final String letter;
  final int day;
  final bool selected;
  final bool isToday;
  final List<Color> dots;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppTheme.onAccent;
    return Material(
      color: selected ? AppTheme.onAccent : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Text(letter,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppTheme.mutedText,
                  )),
              const SizedBox(height: 2),
              Text('$day',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: (isToday && !selected) ? AppTheme.accentPink : fg,
                  )),
              const SizedBox(height: 4),
              // Fixed height so days with and without dots line up.
              SizedBox(
                height: 5,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final c in dots)
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          color: selected ? Colors.white : c,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

