import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/events/utils/event_display.dart';

/// #789 — "Day N of M" eyebrow badge is driven by [liveTripDay]. The helper is
/// live-only (today within [start, end]) and multi-day-only, with UTC-anchored
/// date-only comparison so time-of-day and DST never shift the count.
void main() {
  group('liveTripDay', () {
    final start = DateTime(2026, 7, 10);
    final end = DateTime(2026, 7, 20); // 11-day inclusive span

    test('null start → null', () {
      expect(liveTripDay(null, end, DateTime(2026, 7, 12)), isNull);
    });

    test('null end → null', () {
      expect(liveTripDay(start, null, DateTime(2026, 7, 12)), isNull);
    });

    test('before the trip starts → null', () {
      expect(liveTripDay(start, end, DateTime(2026, 7, 5)), isNull);
      // day before start is still not started
      expect(liveTripDay(start, end, DateTime(2026, 7, 9, 23, 59)), isNull);
    });

    test('on the start date → day 1', () {
      expect(
        liveTripDay(start, end, DateTime(2026, 7, 10, 8)),
        (currentDay: 1, totalDays: 11),
      );
    });

    test('mid-trip → day N (time-of-day ignored)', () {
      expect(
        liveTripDay(start, end, DateTime(2026, 7, 13, 23, 59)),
        (currentDay: 4, totalDays: 11),
      );
    });

    test('on the end date → day M', () {
      expect(
        liveTripDay(start, end, DateTime(2026, 7, 20, 1)),
        (currentDay: 11, totalDays: 11),
      );
    });

    test('after the trip ends → null', () {
      expect(liveTripDay(start, end, DateTime(2026, 7, 21)), isNull);
    });

    test('single-day event (start == end) → null (not multi-day)', () {
      final d = DateTime(2026, 7, 10);
      expect(liveTripDay(d, d, DateTime(2026, 7, 10, 12)), isNull);
    });

    test('two-day trip → day 1 then day 2', () {
      final s = DateTime(2026, 7, 10);
      final e = DateTime(2026, 7, 11);
      expect(
        liveTripDay(s, e, DateTime(2026, 7, 10, 6)),
        (currentDay: 1, totalDays: 2),
      );
      expect(
        liveTripDay(s, e, DateTime(2026, 7, 11, 23)),
        (currentDay: 2, totalDays: 2),
      );
    });

    test('inverted range (end before start) → null', () {
      expect(liveTripDay(end, start, DateTime(2026, 7, 12)), isNull);
    });
  });
}
