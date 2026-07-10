import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/utils/calendar_date.dart';

void main() {
  group('anchorCalendarDate', () {
    test('naive local date anchors to UTC noon of the same y/m/d', () {
      final anchor = anchorCalendarDate(DateTime(2026, 7, 10));
      expect(anchor.isUtc, isTrue);
      expect(anchor.hour, 12);
      expect(anchor, DateTime.utc(2026, 7, 10, 12));
      expect(anchor.toIso8601String(), '2026-07-10T12:00:00.000Z');
    });

    test('is idempotent for an already-anchored value', () {
      final once = anchorCalendarDate(DateTime(2026, 7, 10));
      final twice = anchorCalendarDate(once);
      expect(twice, once);
    });

    test('discards time-of-day, keeps the calendar date', () {
      final anchor = anchorCalendarDate(DateTime(2026, 12, 31, 23, 59));
      expect(anchor, DateTime.utc(2026, 12, 31, 12));
    });

    test('round-trips through Firestore Timestamp types', () {
      final anchor = anchorCalendarDate(DateTime(2026, 7, 10));
      final back = Timestamp.fromDate(anchor).toDate().toUtc();
      expect(back.year, 2026);
      expect(back.month, 7);
      expect(back.day, 10);
    });
  });

  group('calendarDayDiff', () {
    test('same calendar day is 0 regardless of time-of-day', () {
      final a = DateTime(2026, 7, 10, 1, 30);
      final b = DateTime(2026, 7, 10, 22, 45);
      expect(calendarDayDiff(a, b), 0);
    });

    test('anchored-noon tomorrow vs local-now is 1 regardless of hour', () {
      final now = DateTime.now();
      final tomorrow =
          anchorCalendarDate(DateTime(now.year, now.month, now.day).add(
        const Duration(days: 1),
      ));
      expect(calendarDayDiff(now, tomorrow), 1);
    });

    test('spans a month boundary correctly', () {
      expect(
        calendarDayDiff(DateTime(2026, 1, 31), DateTime(2026, 2, 2)),
        2,
      );
    });

    test('is negative when b precedes a', () {
      expect(
        calendarDayDiff(DateTime(2026, 7, 10), DateTime(2026, 7, 8)),
        -2,
      );
    });
  });
}
