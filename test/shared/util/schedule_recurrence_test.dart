import 'package:flutter_test/flutter_test.dart';
import 'package:kawankecil/core/models/schedule.dart';
import 'package:kawankecil/shared/util/schedule_recurrence.dart';

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
  group('once', () {
    test('occurs only on its anchor date (same Y-M-D)', () {
      final e = _entry(recurrence: 'once', anchorDate: DateTime(2026, 9, 15));
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 15)), isTrue);
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 15, 23, 59)), isTrue); // time ignored
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 14)), isFalse);
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 16)), isFalse);
      expect(scheduleEntryOccursOn(e, DateTime(2027, 9, 15)), isFalse); // a year later
    });

    test('null anchorDate never occurs', () {
      expect(scheduleEntryOccursOn(_entry(recurrence: 'once'), DateTime(2026, 9, 15)), isFalse);
    });
  });

  group('daily', () {
    final e = _entry(recurrence: 'daily');
    test('true Mon-Fri, false Sat/Sun, across a month boundary', () {
      for (var d = 7; d <= 11; d++) {
        expect(scheduleEntryOccursOn(e, DateTime(2026, 9, d)), isTrue, reason: 'day $d');
      }
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 12)), isFalse); // Sat
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 13)), isFalse); // Sun
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 30)), isTrue);  // Wed
      expect(scheduleEntryOccursOn(e, DateTime(2026, 10, 1)), isTrue);  // Thu
    });
  });

  group('weekly', () {
    test('matches only its day-of-week', () {
      final e = _entry(recurrence: 'weekly', day: 'Wednesday');
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 9)), isTrue);   // Wed
      expect(scheduleEntryOccursOn(e, DateTime(2026, 9, 10)), isFalse); // Thu
    });
  });

  test('an unknown recurrence never occurs', () {
    expect(scheduleEntryOccursOn(_entry(recurrence: 'monthly', anchorDate: DateTime(2026, 1, 1)),
        DateTime(2026, 2, 1)), isFalse);
  });
}
