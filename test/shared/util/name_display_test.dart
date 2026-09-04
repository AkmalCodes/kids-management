import 'package:flutter_test/flutter_test.dart';
import 'package:kids_management/shared/util/name_display.dart';

void main() {
  group('shortLabelName', () {
    test('single word is returned unchanged', () {
      expect(shortLabelName('Alice'), 'Alice');
    });

    test('two words become first word + last initial', () {
      expect(shortLabelName('Ammar Ali'), 'Ammar A.');
    });

    test('three or more words become first word + last initial', () {
      expect(
        shortLabelName('Muhammad Aariz Danish bin Abdul Rahman'),
        'Muhammad R.',
      );
    });

    test('empty or whitespace-only returns an empty string', () {
      expect(shortLabelName(''), '');
      expect(shortLabelName('   '), '');
    });

    test('leading and internal extra whitespace is ignored', () {
      expect(shortLabelName('  Ammar   Ali  '), 'Ammar A.');
    });

    test('the trailing initial is upper-cased even when the name is lower-case', () {
      expect(shortLabelName('nur aisyah'), 'nur A.');
    });

    test('a single-character last word still yields an initial', () {
      expect(shortLabelName('Ali A'), 'Ali A.');
    });
  });
}
