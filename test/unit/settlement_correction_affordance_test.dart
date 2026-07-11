import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/utils/settlement_correction_affordance.dart';

// #889 — pure unit coverage for the client mirror of the callables' bounded-
// legacy correction detector. These functions drive the SOLO Correct-button
// hide (settle_up_page_body.dart's button gate, NOT the note-based display
// line) and the LogicalHistoryRow/`_correctLogicalSettleUp` write-affordance.

const _sentinel = 'Correction of a recorded payment'; // en sentinel

Settlement _s(
  String id, {
  String payer = 'uid-bob',
  String recipient = 'uid-alice',
  String amount = '10.000',
  String? note,
  String? correctionOfSettlementId,
  bool isDeleted = false,
}) =>
    Settlement(
      id: id,
      tripId: 'event-1',
      payerParticipantId: payer,
      recipientParticipantId: recipient,
      amount: Decimal.parse(amount),
      currency: 'OMR',
      settledAt: DateTime(2026, 5, 17),
      note: note,
      isDeleted: isDeleted,
      correctionOfSettlementId: correctionOfSettlementId,
    );

void main() {
  group('isSoloCorrectionHidden (#889)', () {
    test('a marked settlement hides the Correct affordance', () {
      final marked = _s('rev-1', correctionOfSettlementId: 'orig-1');
      expect(isSoloCorrectionHidden(marked, [marked]), isTrue);
    });

    test(
      'a source row with a LIVE bounded-legacy (exact-inverse, sentinel-'
      'noted, unmarked) correction pointed at it hides the affordance',
      () {
        final source = _s('orig-1', payer: 'uid-bob', recipient: 'uid-alice');
        final legacyReverse = _s(
          'orig-1-rev',
          payer: 'uid-alice',
          recipient: 'uid-bob',
          note: _sentinel,
        );
        final visible = [source, legacyReverse];
        expect(isSoloCorrectionHidden(source, visible), isTrue);
      },
    );

    test(
      'a sentinel-note settlement with NO exact inverse source stays '
      'correctable (coincidental sentinel text is not proof of a correction)',
      () {
        final coincidental = _s('x1', note: _sentinel);
        expect(isSoloCorrectionHidden(coincidental, [coincidental]), isFalse);
      },
    );

    test('a normal unmarked, non-sentinel-note settlement stays correctable', () {
      final normal = _s('n1');
      expect(isSoloCorrectionHidden(normal, [normal]), isFalse);
    });

    test(
      'a deleted candidate source does not count as having a live legacy '
      'correction pointed at it',
      () {
        final source = _s('orig-1', payer: 'uid-bob', recipient: 'uid-alice');
        final legacyReverse = _s(
          'orig-1-rev',
          payer: 'uid-alice',
          recipient: 'uid-bob',
          note: _sentinel,
          isDeleted: true,
        );
        expect(isSoloCorrectionHidden(source, [source, legacyReverse]), isFalse);
      },
    );

    test(
      'money mismatch (different amount) does not count as an exact inverse',
      () {
        final source = _s('orig-1', payer: 'uid-bob', recipient: 'uid-alice');
        final unrelatedSentinelNote = _s(
          'other-1',
          payer: 'uid-alice',
          recipient: 'uid-bob',
          amount: '5.000',
          note: _sentinel,
        );
        expect(
          isSoloCorrectionHidden(source, [source, unrelatedSentinelNote]),
          isFalse,
        );
      },
    );
  });

  group('logicalSetAffordanceCorrected (#889)', () {
    test('empty set never hides (defensive)', () {
      expect(logicalSetAffordanceCorrected(const []), isFalse);
    });

    test('a single original with no reverse keeps the action available', () {
      final original = _s('e1');
      expect(logicalSetAffordanceCorrected([original]), isFalse);
    });

    test('a marked reverse pointed at the sole original hides the action', () {
      final original = _s('e1');
      final reverse = _s(
        'e1-rev',
        payer: 'uid-alice',
        recipient: 'uid-bob',
        note: _sentinel,
        correctionOfSettlementId: 'e1',
      );
      expect(logicalSetAffordanceCorrected([original, reverse]), isTrue);
    });
  });

  group('settlementPartiesAreCurrentMembers (#1149)', () {
    const memberIds = {'uid-alice', 'uid-bob', 'deleted-ghost1'};

    test('both parties live members', () {
      expect(
        settlementPartiesAreCurrentMembers(_s('s1'), memberIds),
        isTrue,
      );
    });

    test('ghost party stays correctable (tombstone id IS in memberIds)', () {
      expect(
        settlementPartiesAreCurrentMembers(
          _s('s2', payer: 'deleted-ghost1'),
          memberIds,
        ),
        isTrue,
      );
    });

    test('departed recipient hides (id absent from memberIds)', () {
      expect(
        settlementPartiesAreCurrentMembers(
          _s('s3', recipient: 'uid-departed'),
          memberIds,
        ),
        isFalse,
      );
    });

    test('null payer id is never current', () {
      final s = Settlement(
        id: 's4',
        tripId: 'event-1',
        recipientParticipantId: 'uid-alice',
        amount: Decimal.parse('10.000'),
        settledAt: DateTime(2026, 5, 17),
      );
      expect(settlementPartiesAreCurrentMembers(s, memberIds), isFalse);
    });
  });
}
