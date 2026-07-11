import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/ledger/models/record_settlement_result.dart';

void main() {
  group('RecordSettlementResult.fromData', () {
    test('parses a full server payload', () {
      final r = RecordSettlementResult.fromData({
        'alreadyRecorded': false,
        'eventScopeWrites': 2,
        'groupScopeWrites': 1,
        'shouldBumpLedgerRevision': true,
        'settledAt': '2026-07-11T12:00:00.000Z',
      });
      expect(r.alreadyRecorded, isFalse);
      expect(r.eventScopeWrites, 2);
      expect(r.groupScopeWrites, 1);
      expect(r.shouldBumpLedgerRevision, isTrue);
      expect(r.settledAt, '2026-07-11T12:00:00.000Z');
    });

    test('idempotent replay payload', () {
      final r = RecordSettlementResult.fromData({
        'alreadyRecorded': true,
        'eventScopeWrites': 1,
        'groupScopeWrites': 0,
        'shouldBumpLedgerRevision': true,
        'settledAt': '2026-07-11T12:00:00.000Z',
      });
      expect(r.alreadyRecorded, isTrue);
    });

    test('null/garbage payloads degrade fail-safe (never throw)', () {
      for (final data in <Object?>[
        null,
        'oops',
        42,
        <Object?>[],
        {'alreadyRecorded': 'yes', 'eventScopeWrites': 'two', 'settledAt': 7},
      ]) {
        final r = RecordSettlementResult.fromData(data);
        expect(r.alreadyRecorded, isFalse, reason: '$data');
        expect(r.eventScopeWrites, 0, reason: '$data');
        expect(r.groupScopeWrites, 0, reason: '$data');
        // Fails toward bumping: a spurious refetch beats a stale home balance.
        expect(r.shouldBumpLedgerRevision, isTrue, reason: '$data');
        expect(r.settledAt, '', reason: '$data');
      }
    });

    test('explicit shouldBumpLedgerRevision=false is honored (pure group write)', () {
      final r = RecordSettlementResult.fromData({
        'alreadyRecorded': false,
        'eventScopeWrites': 0,
        'groupScopeWrites': 1,
        'shouldBumpLedgerRevision': false,
        'settledAt': '2026-07-11T12:00:00.000Z',
      });
      expect(r.shouldBumpLedgerRevision, isFalse);
    });
  });
}
