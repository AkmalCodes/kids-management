import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/shared/util/date_display.dart';

void main() {
  group('hourMinute', () {
    test('zero-pads hours and minutes to HH:mm', () {
      expect(hourMinute(DateTime(2026, 9, 2, 6, 5)), '06:05');
    });

    test('uses 24-hour clock, no AM/PM', () {
      expect(hourMinute(DateTime(2026, 9, 2, 14, 32)), '14:32');
      expect(hourMinute(DateTime(2026, 9, 2, 0, 0)), '00:00');
    });
  });
}
