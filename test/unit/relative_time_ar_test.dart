import 'package:flutter_test/flutter_test.dart';
import 'package:safar/l10n/generated/app_localizations_ar.dart';

/// #153 — Arabic relative time must be readable words, not the cryptic
/// single-letter abbreviations (`12 ي`). Money/counts stay Western digits
/// per the #145 numeral decision.
void main() {
  final ar = AppLocalizationsAr();

  test('minutes render a readable word with a Western digit', () {
    final s = ar.activityRelativeMinutes(5);
    expect(s, contains('دقيقة'));
    expect(s, contains('5'));
    expect(s, isNot(equals('5 د')));
  });

  test('hours render a readable word with a Western digit', () {
    final s = ar.activityRelativeHours(3);
    expect(s, contains('ساعة'));
    expect(s, contains('3'));
    expect(s, isNot(equals('3 س')));
  });

  test('days render a readable word with a Western digit', () {
    final s = ar.activityRelativeDays(12);
    expect(s, contains('يوم'));
    expect(s, contains('12'));
    expect(s, isNot(equals('12 ي')));
  });
}
