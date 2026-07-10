import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/utils/calendar_date.dart';
import 'package:safar/core/utils/localized_dates.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/utils/event_display.dart';
import 'package:safar/features/events/utils/trip_receipt_format.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// Cross-device regression coverage for #1098: an event's picked calendar date
/// must render as that same calendar date on every device in every timezone.
/// The carrier is a UTC-noon-anchored DateTime; every assertion below is
/// machine-timezone-INDEPENDENT (isUtc / epoch / own-component reads).
Event _event({DateTime? startDate, DateTime? endDate}) => Event(
      id: 'e1',
      name: 'N',
      type: EventType.trip,
      groupId: 'g1',
      createdBy: 'u1',
      participantIds: const ['u1'],
      participantNames: const {'u1': 'A'},
      modules: const EventModules(),
      startDate: startDate,
      endDate: endDate,
      createdAt: DateTime(2026, 3, 1),
    );

Future<DocumentSnapshot> _writeAndRead(
  FakeFirebaseFirestore db,
  Map<String, dynamic> data,
) async {
  await db.collection('events').doc('e1').set(data);
  return db.collection('events').doc('e1').get();
}

void main() {
  group('#1098 write-side', () {
    test('toFirestoreMap stores an anchored startDate at exactly UTC noon', () {
      final map = _event(
        startDate: anchorCalendarDate(DateTime(2026, 7, 10)),
        endDate: anchorCalendarDate(DateTime(2026, 7, 12)),
      ).toFirestoreMap();

      final start = map['startDate'] as Timestamp;
      final end = map['endDate'] as Timestamp;
      expect(
        start.millisecondsSinceEpoch,
        DateTime.utc(2026, 7, 10, 12).millisecondsSinceEpoch,
      );
      expect(
        end.millisecondsSinceEpoch,
        DateTime.utc(2026, 7, 12, 12).millisecondsSinceEpoch,
      );
    });
  });

  group('#1098 read-side (core regression)', () {
    late FakeFirebaseFirestore db;
    setUp(() => db = FakeFirebaseFirestore());

    test('fromDoc yields a UTC-flagged date holding the picked calendar day',
        () async {
      final snap = await _writeAndRead(db, {
        'name': 'Beach',
        'type': 'trip',
        'groupId': 'g1',
        'createdBy': 'u1',
        'participantIds': const ['u1'],
        'participantNames': const {'u1': 'A'},
        'modules': const {'ledger': true},
        'createdAt': '2026-03-01T00:00:00Z',
        'startDate': Timestamp.fromDate(DateTime.utc(2026, 7, 10, 12)),
        'endDate': Timestamp.fromDate(DateTime.utc(2026, 7, 12, 12)),
      });

      final event = Event.fromDoc(snap);
      expect(event.startDate!.isUtc, isTrue);
      expect(event.startDate!.day, 10);
      expect(event.endDate!.isUtc, isTrue);
      expect(event.endDate!.day, 12);
    });
  });

  group('#1098 formatter pass-through (invariant holds, formatters untouched)',
      () {
    test('receiptDate renders the anchored calendar date', () {
      expect(receiptDate(anchorCalendarDate(DateTime(2026, 7, 10))),
          '2026-07-10');
      expect(
        receiptDateRange(
          anchorCalendarDate(DateTime(2026, 7, 10)),
          anchorCalendarDate(DateTime(2026, 7, 12)),
        ),
        '2026-07-10 – 2026-07-12',
      );
    });

    test('liveTripDay counts the anchored span from the picked start', () {
      final live = liveTripDay(
        anchorCalendarDate(DateTime(2026, 7, 9)),
        anchorCalendarDate(DateTime(2026, 7, 12)),
        DateTime(2026, 7, 10),
      );
      expect(live, isNotNull);
      expect(live!.currentDay, 2);
      expect(live.totalDays, 4);
    });

    testWidgets('formatShortMonthDay / formatDateRangeShort render the day',
        (tester) async {
      late String short;
      late String range;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              short = formatShortMonthDay(
                context,
                anchorCalendarDate(DateTime(2026, 7, 10)),
              );
              range = formatDateRangeShort(
                context,
                anchorCalendarDate(DateTime(2026, 7, 10)),
                anchorCalendarDate(DateTime(2026, 7, 12)),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(short, contains('10'));
      expect(short, contains('Jul'));
      expect(range, contains('10'));
      expect(range, contains('12'));
    });
  });

  group('#1098 legacy doc (accepted-shift, decision 2)', () {
    late FakeFirebaseFirestore db;
    setUp(() => db = FakeFirebaseFirestore());

    test('a local-midnight legacy instant parses to a non-null UTC-flagged date',
        () async {
      final snap = await _writeAndRead(db, {
        'name': 'Legacy',
        'type': 'trip',
        'groupId': 'g1',
        'createdBy': 'u1',
        'participantIds': const ['u1'],
        'participantNames': const {'u1': 'A'},
        'modules': const {'ledger': true},
        'createdAt': '2026-03-01T00:00:00Z',
        'startDate': Timestamp.fromDate(DateTime(2026, 7, 10)),
      });

      final event = Event.fromDoc(snap);
      expect(event.startDate, isNotNull);
      expect(event.startDate!.isUtc, isTrue);
    });
  });
}
