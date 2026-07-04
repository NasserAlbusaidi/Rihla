import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/groups/widgets/settle_up_page_body.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';

// #753 — groupSettlementHistory collapses a settle-up history into display rows:
// each groupSettleUpId-tagged set → ONE LogicalHistoryRow (amount = Σ of its
// non-correction docs); untagged docs stay individual SoloHistoryRows, in the
// incoming (newest-first) order. A logical row reads "corrected" once any tagged
// doc carries the correction-note sentinel.

const String note = 'Correction of a recorded payment'; // en sentinel

Settlement _s(
  String id, {
  String? groupSettleUpId,
  String amount = '5.000',
  String? settlementNote,
  DateTime? at,
  String payer = 'uid-sara',
  String recipient = 'uid-ahmed',
  String scope = 'event',
  String? correctionOfSettlementId,
}) =>
    Settlement(
      id: id,
      tripId: 'event-1',
      payerParticipantId: payer,
      recipientParticipantId: recipient,
      amount: Decimal.parse(amount),
      currency: 'OMR',
      settledAt: at ?? DateTime(2026, 6, 29),
      payerName: 'Sara',
      recipientName: 'Ahmed',
      scope: scope,
      note: settlementNote,
      groupSettleUpId: groupSettleUpId,
      correctionOfSettlementId: correctionOfSettlementId,
    );

void main() {
  group('#753 groupSettlementHistory', () {
    test('untagged docs all become solo rows, order preserved', () {
      final rows = groupSettlementHistory([
        _s('a', at: DateTime(2026, 6, 29)),
        _s('b', at: DateTime(2026, 6, 28)),
      ]);
      expect(rows.length, 2);
      expect(rows.every((r) => r is SoloHistoryRow), isTrue);
      expect((rows[0] as SoloHistoryRow).settlement.id, 'a');
      expect((rows[1] as SoloHistoryRow).settlement.id, 'b');
    });

    test('one tagged event doc → one logical row, total = its amount', () {
      final rows = groupSettlementHistory([
        _s('e1', groupSettleUpId: 'X', amount: '5.000'),
      ]);
      expect(rows.length, 1);
      final row = rows.single as LogicalHistoryRow;
      expect(row.groupSettleUpId, 'X');
      expect(row.totalAmount, Decimal.parse('5.000'));
      expect(row.isCorrected, isFalse);
      expect(row.representative.payerParticipantId, 'uid-sara');
    });

    test('multi-doc tagged set → one logical row, total = Σ of originals', () {
      final rows = groupSettlementHistory([
        _s('e1', groupSettleUpId: 'X', amount: '3.000'),
        _s('e2', groupSettleUpId: 'X', amount: '2.000'),
        _s('res', groupSettleUpId: 'X', amount: '1.000', scope: 'group'),
      ]);
      expect(rows.length, 1);
      final row = rows.single as LogicalHistoryRow;
      expect(row.totalAmount, Decimal.parse('6.000'));
      expect(row.isCorrected, isFalse);
    });

    test('a tagged set with its reverses reads isCorrected, total = originals',
        () {
      final rows = groupSettlementHistory([
        _s('e1', groupSettleUpId: 'X', amount: '5.000'),
        // the offsetting reverse (swap + correction note), tagged X.
        _s('e1-rev',
            groupSettleUpId: 'X',
            amount: '5.000',
            settlementNote: note,
            payer: 'uid-ahmed',
            recipient: 'uid-sara',
            at: DateTime(2026, 6, 30)),
      ]);
      expect(rows.length, 1);
      final row = rows.single as LogicalHistoryRow;
      expect(row.isCorrected, isTrue);
      expect(row.totalAmount, Decimal.parse('5.000'),
          reason: 'total folds ONLY the non-correction originals');
      expect(row.representative.payerParticipantId, 'uid-sara',
          reason: 'direction from the original, not the reverse');
    });

    test('mixed untagged + tagged: counts and types', () {
      final rows = groupSettlementHistory([
        _s('solo1', at: DateTime(2026, 6, 30)),
        _s('e1', groupSettleUpId: 'X', amount: '4.000', at: DateTime(2026, 6, 29)),
        _s('e2', groupSettleUpId: 'X', amount: '4.000', at: DateTime(2026, 6, 29)),
        _s('solo2', at: DateTime(2026, 6, 28)),
      ]);
      expect(rows.length, 3);
      expect(rows[0], isA<SoloHistoryRow>());
      expect(rows[1], isA<LogicalHistoryRow>(),
          reason: 'logical row sits at its newest member position');
      expect(rows[2], isA<SoloHistoryRow>());
      expect((rows[1] as LogicalHistoryRow).totalAmount, Decimal.parse('8.000'));
    });

    test('defensive: a tagged set with ONLY correction docs renders as solos',
        () {
      final rows = groupSettlementHistory([
        _s('orphan', groupSettleUpId: 'X', settlementNote: note),
      ]);
      expect(rows.length, 1);
      expect(rows.single, isA<SoloHistoryRow>(),
          reason: 'no original → never a phantom logical row');
    });
  });

  // #889 — isCorrected (display, note-based) and affordanceCorrected
  // (marker/bounded-legacy) are SEPARATE fields on LogicalHistoryRow. Only
  // affordanceCorrected drives the write-affordance null-ing at
  // settle_up_page_body.dart's onCorrectLogical site.
  group('#889 LogicalHistoryRow.affordanceCorrected', () {
    test('a MARKED reverse hides the affordance (both signals agree)', () {
      final rows = groupSettlementHistory([
        _s('e1', groupSettleUpId: 'X', amount: '5.000'),
        _s(
          'e1-rev',
          groupSettleUpId: 'X',
          amount: '5.000',
          settlementNote: note,
          payer: 'uid-ahmed',
          recipient: 'uid-sara',
          at: DateTime(2026, 6, 30),
          correctionOfSettlementId: 'e1',
        ),
      ]);
      final row = rows.single as LogicalHistoryRow;
      expect(row.isCorrected, isTrue);
      expect(row.affordanceCorrected, isTrue);
    });

    test(
      'a bounded-legacy note-only reverse (pre-#889, exact inverse, no '
      'marker) also hides the affordance — the migration case',
      () {
        final rows = groupSettlementHistory([
          _s('e1', groupSettleUpId: 'X', amount: '5.000'),
          _s(
            'e1-rev',
            groupSettleUpId: 'X',
            amount: '5.000',
            settlementNote: note,
            payer: 'uid-ahmed',
            recipient: 'uid-sara',
            at: DateTime(2026, 6, 30),
          ),
        ]);
        final row = rows.single as LogicalHistoryRow;
        expect(row.isCorrected, isTrue);
        expect(row.affordanceCorrected, isTrue);
      },
    );

    test(
      'a coincidental sentinel-note member with NO exact inverse in the set '
      'keeps isCorrected true for display but affordanceCorrected false — '
      'stays correctable (a normal payment note can equal the sentinel)',
      () {
        // e2's note happens to equal the sentinel but is NOT an offsetting
        // reverse of e1 (same direction, not swapped) — a genuine second
        // payment, not a correction. e1 stays the non-correction original so
        // the set still folds into a LogicalHistoryRow (not the defensive
        // solo-render path, which only fires when EVERY member is
        // sentinel-noted).
        final rows = groupSettlementHistory([
          _s('e1', groupSettleUpId: 'X', amount: '5.000'),
          _s(
            'e2',
            groupSettleUpId: 'X',
            amount: '3.000',
            settlementNote: note,
            at: DateTime(2026, 6, 30),
          ),
        ]);
        final row = rows.single as LogicalHistoryRow;
        expect(row.isCorrected, isTrue);
        expect(row.affordanceCorrected, isFalse);
      },
    );

    test(
      'a partially-marked set (2 originals, only 1 reversed) keeps the '
      'action available so the callable can repair the remainder',
      () {
        final rows = groupSettlementHistory([
          _s('e1', groupSettleUpId: 'X', amount: '3.000'),
          _s('e2', groupSettleUpId: 'X', amount: '2.000'),
          _s(
            'e1-rev',
            groupSettleUpId: 'X',
            amount: '3.000',
            settlementNote: note,
            payer: 'uid-ahmed',
            recipient: 'uid-sara',
            at: DateTime(2026, 6, 30),
            correctionOfSettlementId: 'e1',
          ),
        ]);
        final row = rows.single as LogicalHistoryRow;
        expect(row.affordanceCorrected, isFalse);
      },
    );

    test('no reverse at all keeps the action available', () {
      final rows = groupSettlementHistory([
        _s('e1', groupSettleUpId: 'X', amount: '5.000'),
      ]);
      final row = rows.single as LogicalHistoryRow;
      expect(row.isCorrected, isFalse);
      expect(row.affordanceCorrected, isFalse);
    });
  });
}
