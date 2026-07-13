import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/utils/bidi.dart';

void main() {
  group('bidiIsolate', () {
    test('wraps in FSI (U+2068) … PDI (U+2069)', () {
      expect(bidiIsolate('Ali'), '\u{2068}Ali\u{2069}');
    });

    test('isolates a name carrying an unterminated RLO', () {
      // U+202E is RLO; without the isolate it reorders the surrounding text.
      const evil = 'Ali\u{202E}';
      final wrapped = bidiIsolate(evil);
      expect(wrapped.codeUnits.first, 0x2068);
      expect(wrapped.codeUnits.last, 0x2069);
      expect(wrapped, '\u{2068}$evil\u{2069}');
    });

    test('wraps an empty string to the two-char isolate pair', () {
      // Documents the length-2 result — the notification-string fallbacks must
      // derive their local BEFORE wrapping so empty checks still fire.
      expect(bidiIsolate(''), '\u{2068}\u{2069}');
      expect(bidiIsolate('').length, 2);
    });
  });
}
