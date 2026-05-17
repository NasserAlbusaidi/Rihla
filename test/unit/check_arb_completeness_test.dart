import 'package:flutter_test/flutter_test.dart';

// Tool scripts in `tool/` are not packaged — import relatively.
import '../../tool/check_arb_completeness.dart' as checker;

void main() {
  test('matching key sets pass', () {
    final result = checker.compare(
      en: {'@@locale': 'en', 'offlineBannerMessage': 'X'},
      ar: {'@@locale': 'ar', 'offlineBannerMessage': 'Y'},
    );
    expect(result.missingInAr, isEmpty);
    expect(result.extraInAr, isEmpty);
  });

  test('detects keys present in en but missing in ar', () {
    final result = checker.compare(
      en: {'@@locale': 'en', 'a': '1', 'b': '2'},
      ar: {'@@locale': 'ar', 'a': '1'},
    );
    expect(result.missingInAr, ['b']);
  });

  test('detects keys present in ar but missing in en', () {
    final result = checker.compare(
      en: {'@@locale': 'en', 'a': '1'},
      ar: {'@@locale': 'ar', 'a': '1', 'extra': 'x'},
    );
    expect(result.extraInAr, ['extra']);
  });

  test('ignores @-prefixed metadata keys', () {
    final result = checker.compare(
      en: {'@@locale': 'en', 'a': '1', '@a': {'description': 'doc'}},
      ar: {'@@locale': 'ar', 'a': '1'},
    );
    expect(result.missingInAr, isEmpty);
  });
}
