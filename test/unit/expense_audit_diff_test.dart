import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/activity/utils/expense_audit_diff.dart';

/// PR 3 (#248) — the pure parse/diff layer over the `expenseAuditLogger`
/// trigger's `metadata.before/after`. Defensive: legacy/malformed metadata must
/// degrade to "no detail", never throw.
void main() {
  Map<String, dynamic> snap({
    int amountFils = 10500,
    String currency = 'OMR',
    String? payer = 'p1',
    String? description = 'Dinner',
    bool isDeleted = false,
  }) => {
    'amountFils': amountFils,
    'currency': currency,
    'payerParticipantId': payer,
    'description': description,
    'isDeleted': isDeleted,
  };

  group('ExpenseAuditDiff.fromMetadata', () {
    test('CREATE: before null, after present, has detail, no field change', () {
      final d = ExpenseAuditDiff.fromMetadata({
        'expenseId': 'e1',
        'before': null,
        'after': snap(),
      });
      expect(d.before, isNull);
      expect(d.after, isNotNull);
      expect(d.hasDetail, isTrue);
      expect(d.hasFieldChange, isFalse); // no before → nothing to diff
    });

    test('amount: 10500 OMR parses to Decimal 10.5 (scale 1000)', () {
      final d = ExpenseAuditDiff.fromMetadata({'after': snap(amountFils: 10500)});
      expect(d.after!.amount, Decimal.parse('10.5'));
      expect(d.after!.currency, 'OMR');
    });

    test('UPDATE amount change flips only amountChanged', () {
      final d = ExpenseAuditDiff.fromMetadata({
        'before': snap(amountFils: 10500),
        'after': snap(amountFils: 12500),
      });
      expect(d.amountChanged, isTrue);
      expect(d.descriptionChanged, isFalse);
      expect(d.payerChanged, isFalse);
      expect(d.hasFieldChange, isTrue);
    });

    test('UPDATE description change flips only descriptionChanged', () {
      final d = ExpenseAuditDiff.fromMetadata({
        'before': snap(description: 'Dinner'),
        'after': snap(description: 'Late dinner'),
      });
      expect(d.descriptionChanged, isTrue);
      expect(d.amountChanged, isFalse);
      expect(d.payerChanged, isFalse);
    });

    test('UPDATE payer change flips only payerChanged', () {
      final d = ExpenseAuditDiff.fromMetadata({
        'before': snap(payer: 'p1'),
        'after': snap(payer: 'p2'),
      });
      expect(d.payerChanged, isTrue);
      expect(d.amountChanged, isFalse);
      expect(d.descriptionChanged, isFalse);
    });

    test('UPDATE with identical money snaps has no field change (split-only edit)', () {
      final d = ExpenseAuditDiff.fromMetadata({
        'before': snap(),
        'after': snap(),
      });
      expect(d.hasDetail, isTrue);
      expect(d.hasFieldChange, isFalse); // → caller renders the summary fallback
    });

    test('amountFils as num/double is coerced (no throw)', () {
      final d = ExpenseAuditDiff.fromMetadata({
        'after': {'amountFils': 8000.0, 'currency': 'OMR'},
      });
      expect(d.after, isNotNull);
      expect(d.after!.amount, Decimal.parse('8'));
    });

    test('legacy empty metadata → no detail', () {
      final d = ExpenseAuditDiff.fromMetadata(<String, dynamic>{});
      expect(d.hasDetail, isFalse);
      expect(d.before, isNull);
      expect(d.after, isNull);
    });

    test('malformed after (missing amountFils) → no detail', () {
      final d = ExpenseAuditDiff.fromMetadata({
        'after': {'currency': 'OMR', 'description': 'x'},
      });
      expect(d.after, isNull);
      expect(d.hasDetail, isFalse);
    });

    test('after with empty currency → no detail', () {
      final d = ExpenseAuditDiff.fromMetadata({
        'after': {'amountFils': 100, 'currency': ''},
      });
      expect(d.after, isNull);
    });

    test('before as a non-map → before null, after treated as create summary', () {
      final d = ExpenseAuditDiff.fromMetadata({
        'before': 'garbage',
        'after': snap(),
      });
      expect(d.before, isNull);
      expect(d.after, isNotNull);
      expect(d.hasFieldChange, isFalse);
    });

    test('empty/whitespace description and null payer normalize to null', () {
      final d = ExpenseAuditDiff.fromMetadata({
        'after': snap(description: '', payer: null),
      });
      expect(d.after!.description, isNull);
      expect(d.after!.payerParticipantId, isNull);
    });
  });
}
