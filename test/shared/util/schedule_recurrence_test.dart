import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/core/models/schedule.dart';
import 'package:kids_management/shared/util/schedule_recurrence.dart';

ScheduleEntry _entry({
  required String recurrence,
  String day = 'Monday',
  DateTime? anchorDate,
}) =>
    ScheduleEntry(
      id: 'e1',
      type: 'class',
      refId: 'c1',
      centerId: 'ctr1',
      day: day,
      startTime: '08:00',
      endTime: '09:00',
      label: 'X',
      color: '26A69A',
      recurrence: recurrence,
      anchorDate: anchorDate,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      createdBy: 'u1',
      updatedBy: 'u1',
    );

void main() {
  group('daily', () {
    final e = _entry(recurrence: 'daily');
    test('true Mon–Fri, false Sat/Sun', () {
      // 2026-09-07 is a Monday.
      for (var d = 7; d <= 11; d++) {
        expect(scheduleEntryOccursOn(e, DateTime(2026, 9, d)), isTrue, reason: 'day $d');
      }
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 12)), isFalse); // Sat
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 13)), isFalse); // Sun
    });

    test('daily does not break at month boundary', () {
      // Wed 30 Sep 2026 and Thu 1 Oct 2026 (different months, both weekdays)
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 30)), isTrue);  // Wed
      expect(scheduleEntryOccursOn(e, DateTime(2026, 10, 1)), isTrue);  // Thu
      // Sat 3 Oct 2026 should be false
      expect(scheduleEntryOccursOn(e, DateTime(2026, 10, 3)), isFalse); // Sat
    });
  });

  group('weekly', () {
    test('matches only its day-of-week', () {
      final e = _entry(recurrence: 'weekly', day: 'Wednesday');
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 9)), isTrue);  // Wed
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 10)), isFalse); // Thu
    });
  });

  group('monthly', () {
    test('the 15th every month', () {
      final e = _entry(recurrence: 'monthly', anchorDate: DateTime(2026, 1, 15));
      expect(scheduleEntryOccursOn(e, DateTime(2026, 2, 15)), isTrue);
      expect(scheduleEntryOccursOn(e, DateTime(2026, 2, 14)), isFalse);
      // No-clamp path: 15th in a 30-day month (April) and 31-day month (March)
      expect(scheduleEntryOccursOn(e, DateTime(2026, 4, 15)), isTrue);  // 30-day month
      expect(scheduleEntryOccursOn(e, DateTime(2026, 3, 15)), isTrue);  // 31-day month
      expect(scheduleEntryOccursOn(e, DateTime(2026, 3, 16)), isFalse);
    });

    test('the 31st clamps to the last day of shorter months', () {
      final e = _entry(recurrence: 'monthly', anchorDate: DateTime(2026, 1, 31));
      expect(scheduleEntryOccursOn(e, DateTime(2026, 1, 31)), isTrue);
      expect(scheduleEntryOccursOn(e, DateTime(2026, 2, 28)), isTrue);  // 2026 common year
      expect(scheduleEntryOccursOn(e, DateTime(2026, 2, 27)), isFalse);
      expect(scheduleEntryOccursOn(e, DateTime(2028, 2, 29)), isTrue);  // 2028 leap
      expect(scheduleEntryOccursOn(e, DateTime(2028, 2, 28)), isFalse);
      expect(scheduleEntryOccursOn(e, DateTime(2026, 4, 30)), isTrue);
      expect(scheduleEntryOccursOn(e, DateTime(2026, 4, 29)), isFalse);
    });

    test('null anchorDate never occurs (defensive)', () {
      final e = _entry(recurrence: 'monthly', anchorDate: null);
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 15)), isFalse);
    });
  });

  group('annually', () {
    test('a normal date, every year', () {
      final e = _entry(recurrence: 'annually', anchorDate: DateTime(2026, 3, 15));
      expect(scheduleEntryOccursOn(e, DateTime(2027, 3, 15)), isTrue);
      expect(scheduleEntryOccursOn(e, DateTime(2027, 3, 14)), isFalse);
      expect(scheduleEntryOccursOn(e, DateTime(2027, 4, 15)), isFalse);
    });

    test('Feb-29 anchor: leap years on the 29th, common years on the 28th', () {
      final e = _entry(recurrence: 'annually', anchorDate: DateTime(2024, 2, 29));
      expect(scheduleEntryOccursOn(e, DateTime(2024, 2, 29)), isTrue);
      expect(scheduleEntryOccursOn(e, DateTime(2025, 2, 28)), isTrue);
      expect(scheduleEntryOccursOn(e, DateTime(2025, 3, 1)), isFalse); // day after the fallback
      expect(scheduleEntryOccursOn(e, DateTime(2026, 2, 28)), isTrue);
      expect(scheduleEntryOccursOn(e, DateTime(2027, 2, 28)), isTrue);
      expect(scheduleEntryOccursOn(e, DateTime(2028, 2, 29)), isTrue);
      expect(scheduleEntryOccursOn(e, DateTime(2028, 2, 28)), isFalse);
    });

    test('null anchorDate never occurs (defensive)', () {
      final e = _entry(recurrence: 'annually', anchorDate: null);
      expect(scheduleEntryOccursOn(e, DateTime(2026, 3, 15)), isFalse);
    });
  });
}
