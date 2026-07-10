import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';

Settlement _settlement({
  required String id,
  required String payerParticipantId,
  required String recipientParticipantId,
}) {
  return Settlement(
    id: id,
    tripId: 'trip1',
    payerParticipantId: payerParticipantId,
    recipientParticipantId: recipientParticipantId,
    amount: Decimal.parse('1.000'),
    settledAt: DateTime.utc(2026, 1, 1),
  );
}

void main() {
  group('SettlementService.deterministicSettlementId', () {
    const baseArgs = (
      scopeKey: 'event:g1:e1',
      payerParticipantId: 'p1',
      recipientParticipantId: 'p2',
      currency: 'OMR',
      pairEpoch: 0,
    );

    String idFor({
      String? scopeKey,
      String? payerParticipantId,
      String? recipientParticipantId,
      String? currency,
      Decimal? amount,
      int? pairEpoch,
    }) =>
        SettlementService.deterministicSettlementId(
          scopeKey: scopeKey ?? baseArgs.scopeKey,
          payerParticipantId:
              payerParticipantId ?? baseArgs.payerParticipantId,
          recipientParticipantId:
              recipientParticipantId ?? baseArgs.recipientParticipantId,
          currency: currency ?? baseArgs.currency,
          amount: amount ?? Decimal.parse('2.900'),
          pairEpoch: pairEpoch ?? baseArgs.pairEpoch,
        );

    test('determinism: same inputs -> same id, twice', () {
      final a = idFor();
      final b = idFor();
      expect(a, b);
    });

    test('id shape: 43 chars, ^sd1[0-9a-f]{40}\$', () {
      final id = idFor();
      expect(id.length, 43);
      expect(RegExp(r'^sd1[0-9a-f]{40}$').hasMatch(id), isTrue);
    });

    // Table-driven: each single perturbation from the base must change the id.
    final base = idFor();
    final perturbations = <String, String Function()>{
      'scopeKey': () => idFor(scopeKey: 'event:g1:e2'),
      'payerParticipantId': () => idFor(payerParticipantId: 'p3'),
      'recipientParticipantId': () => idFor(recipientParticipantId: 'p3'),
      'currency': () => idFor(currency: 'USD'),
      'amount': () => idFor(amount: Decimal.parse('3.000')),
      'pairEpoch': () => idFor(pairEpoch: 1),
    };

    for (final entry in perturbations.entries) {
      test('perturbing ${entry.key} changes the id', () {
        expect(entry.value(), isNot(base));
      });
    }

    test(
      'OMR 2.900 vs JPY 2900 vs USD 29.00 all share amountFils=2900 but '
      'differ by currency -> three distinct ids',
      () {
        final omr = idFor(currency: 'OMR', amount: Decimal.parse('2.900'));
        final jpy = idFor(currency: 'JPY', amount: Decimal.parse('2900'));
        final usd = idFor(currency: 'USD', amount: Decimal.parse('29.00'));
        expect({omr, jpy, usd}.length, 3);
      },
    );
  });

  group('SettlementService.directedPairEpoch', () {
    test('empty list -> 0', () {
      expect(
        SettlementService.directedPairEpoch(
          const [],
          payerParticipantId: 'p1',
          recipientParticipantId: 'p2',
        ),
        0,
      );
    });

    test('reversed pair is NOT counted', () {
      final settlements = [
        _settlement(id: 's1', payerParticipantId: 'p2', recipientParticipantId: 'p1'),
      ];
      expect(
        SettlementService.directedPairEpoch(
          settlements,
          payerParticipantId: 'p1',
          recipientParticipantId: 'p2',
        ),
        0,
      );
    });

    test('other-pair rows are NOT counted', () {
      final settlements = [
        _settlement(id: 's1', payerParticipantId: 'p3', recipientParticipantId: 'p4'),
        _settlement(id: 's2', payerParticipantId: 'p1', recipientParticipantId: 'p2'),
      ];
      expect(
        SettlementService.directedPairEpoch(
          settlements,
          payerParticipantId: 'p1',
          recipientParticipantId: 'p2',
        ),
        1,
      );
    });

    test(
      'counts exactly the list it is given -- caller is responsible for '
      'feeding provider-filtered isDeleted == false rows; the helper is pure '
      'and applies no filtering of its own',
      () {
        final settlements = [
          _settlement(id: 's1', payerParticipantId: 'p1', recipientParticipantId: 'p2'),
          _settlement(id: 's2', payerParticipantId: 'p1', recipientParticipantId: 'p2'),
          _settlement(id: 's3', payerParticipantId: 'p1', recipientParticipantId: 'p2'),
        ];
        expect(
          SettlementService.directedPairEpoch(
            settlements,
            payerParticipantId: 'p1',
            recipientParticipantId: 'p2',
          ),
          3,
        );
      },
    );
  });

  group('SettlementService decompose id derivations', () {
    test('decomposeLegSettlementId is deterministic per (gsuId, eventId)', () {
      final a = SettlementService.decomposeLegSettlementId('gsu1', 'e1');
      final b = SettlementService.decomposeLegSettlementId('gsu1', 'e1');
      expect(a, b);
      expect(RegExp(r'^sd1[0-9a-f]{40}$').hasMatch(a), isTrue);
    });

    test('decomposeLegSettlementId differs across eventId', () {
      final a = SettlementService.decomposeLegSettlementId('gsu1', 'e1');
      final b = SettlementService.decomposeLegSettlementId('gsu1', 'e2');
      expect(a, isNot(b));
    });

    test('decomposeResidualSettlementId is deterministic per gsuId', () {
      final a = SettlementService.decomposeResidualSettlementId('gsu1');
      final b = SettlementService.decomposeResidualSettlementId('gsu1');
      expect(a, b);
      expect(RegExp(r'^sd1[0-9a-f]{40}$').hasMatch(a), isTrue);
    });

    test('leg and residual ids never collide for the same gsuId', () {
      final leg = SettlementService.decomposeLegSettlementId('gsu1', 'e1');
      final residual = SettlementService.decomposeResidualSettlementId('gsu1');
      expect(leg, isNot(residual));
    });
  });
}
