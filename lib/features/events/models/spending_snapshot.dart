import 'package:decimal/decimal.dart';

import '../../../core/services/money_serializer.dart';
import '../../ledger/models/expense_model.dart';
import 'event_recap.dart';

/// The frozen, viewer-independent SPENDING half of an [EventRecap], persisted on
/// the event doc as the opaque `spendingSnapshot` blob when the event is closed
/// (Slice 6 of #202). Settlement status is intentionally NOT here — it stays
/// live (the epic §5 contract).
///
/// OPAQUE & DISPLAY-ONLY: `recomputeNet` / the balance oracle / any Cloud
/// Function NEVER read this field (same contract as `splitExplanation`). Balance
/// truth stays in the expense/settlement docs. So freezing a slightly-stale
/// snapshot can never produce a wrong settle-up — at worst a cosmetic recap.
///
/// Money invariant: every field is a per-currency map keyed by currency code;
/// Decimals are NEVER summed across currencies. Amounts serialize to integer
/// subunits via [MoneySerializer] at the Firestore boundary only.
class SpendingSnapshot {
  /// Schema version stamped into the map (`v`). Bump on a breaking shape change.
  static const int schemaVersion = 1;

  /// Generous opaque top-level entry-count cap, mirrored by `spendingSnapshotBounded`
  /// in `security/firestore.rules`. The 1 MB Firestore doc limit is the real
  /// payload backstop (nested maps are not counted by the rules' `size()`).
  static const int maxTopLevelKeys = 16;

  final int participantCount;
  final int expenseCount;
  final Map<String, Decimal> totalSpentByCurrency;
  final Map<String, RecapExpenseRef> biggestExpenseByCurrency;
  final Map<String, List<RecapPersonAmount>> payerTotalsByCurrency;
  final Map<String, List<RecapCategoryTotal>> categoryTotalsByCurrency;

  /// Per-participant owed per currency (`UserBalance.totalOwed`). The source
  /// [EventRecap] exposes only the *current user's* `userShareByCurrency`, so
  /// this map — built from the full balance bucket — is what lets ANY viewer
  /// reconstruct their own frozen share after close (Gate R1).
  final Map<String, Map<String, Decimal>> owedByCurrency;

  const SpendingSnapshot({
    required this.participantCount,
    required this.expenseCount,
    required this.totalSpentByCurrency,
    required this.biggestExpenseByCurrency,
    required this.payerTotalsByCurrency,
    required this.categoryTotalsByCurrency,
    required this.owedByCurrency,
  });

  /// Capture the frozen spending half. Viewer-independent spending fields come
  /// from [recap]; the per-participant [owedByCurrency] map comes from
  /// [balances] (`UserBalance.totalOwed`), which the recap does not carry.
  factory SpendingSnapshot.from({
    required EventRecap recap,
    required Map<String, List<UserBalance>> balances,
  }) {
    final owed = <String, Map<String, Decimal>>{};
    balances.forEach((ccy, bucket) {
      final m = <String, Decimal>{};
      for (final b in bucket) {
        m[b.participantId] = b.totalOwed;
      }
      owed[ccy] = m;
    });
    return SpendingSnapshot(
      participantCount: recap.participantCount,
      expenseCount: recap.expenseCount,
      totalSpentByCurrency: Map.of(recap.totalSpentByCurrency),
      biggestExpenseByCurrency: Map.of(recap.biggestExpenseByCurrency),
      payerTotalsByCurrency: {
        for (final e in recap.payerTotalsByCurrency.entries)
          e.key: List.of(e.value),
      },
      categoryTotalsByCurrency: {
        for (final e in recap.categoryTotalsByCurrency.entries)
          e.key: List.of(e.value),
      },
      owedByCurrency: owed,
    );
  }

  /// Serialize to the Firestore-ready opaque map. Amounts → integer subunits in
  /// the bucket's currency. Null `desc`/`cat` are omitted. An unsupported
  /// currency (should never reach here — providers fence to supported) is
  /// skipped rather than throwing.
  Map<String, dynamic> toMap() {
    int sub(Decimal v, String ccy) => MoneySerializer.toSubunits(v, ccy);

    final totals = <String, dynamic>{};
    totalSpentByCurrency.forEach((ccy, v) {
      if (MoneySerializer.isSupported(ccy)) totals[ccy] = sub(v, ccy);
    });

    final biggest = <String, dynamic>{};
    biggestExpenseByCurrency.forEach((ccy, ref) {
      if (!MoneySerializer.isSupported(ccy)) return;
      biggest[ccy] = {
        'id': ref.expenseId,
        'amt': sub(ref.amount, ccy),
        if (ref.description != null) 'desc': ref.description,
        if (ref.categoryId != null) 'cat': ref.categoryId,
        'payer': ref.payerId,
      };
    });

    final payers = <String, dynamic>{};
    payerTotalsByCurrency.forEach((ccy, list) {
      if (!MoneySerializer.isSupported(ccy)) return;
      payers[ccy] = [
        for (final p in list) {'id': p.participantId, 'amt': sub(p.amount, ccy)},
      ];
    });

    final categories = <String, dynamic>{};
    categoryTotalsByCurrency.forEach((ccy, list) {
      if (!MoneySerializer.isSupported(ccy)) return;
      categories[ccy] = [
        for (final c in list) {'cat': c.categoryId, 'amt': sub(c.total, ccy)},
      ];
    });

    final owed = <String, dynamic>{};
    owedByCurrency.forEach((ccy, m) {
      if (!MoneySerializer.isSupported(ccy)) return;
      owed[ccy] = {
        for (final e in m.entries) e.key: sub(e.value, ccy),
      };
    });

    return {
      'v': schemaVersion,
      'participantCount': participantCount,
      'expenseCount': expenseCount,
      'totals': totals,
      'biggest': biggest,
      'payers': payers,
      'categories': categories,
      'owed': owed,
    };
  }

  /// TOTAL-PARSE deserialize: NEVER throws on a malformed/forged map (it sits
  /// inside `Event.fromDoc`, which must not error the events stream). Unknown
  /// currencies are dropped; garbage values coerce to safe defaults.
  factory SpendingSnapshot.fromMap(Map<String, dynamic> map) {
    return SpendingSnapshot(
      participantCount: _asInt(map['participantCount']),
      expenseCount: _asInt(map['expenseCount']),
      totalSpentByCurrency: _parseMoneyMap(map['totals']),
      biggestExpenseByCurrency: _parseBiggest(map['biggest']),
      payerTotalsByCurrency: _parsePersonAmounts(map['payers'], 'id'),
      categoryTotalsByCurrency: _parseCategoryTotals(map['categories']),
      owedByCurrency: _parseOwed(map['owed']),
    );
  }

  static int _asInt(dynamic v) =>
      v is int ? v : (v is num ? v.toInt() : 0);

  static Map<String, Decimal> _parseMoneyMap(dynamic raw) {
    final out = <String, Decimal>{};
    if (raw is! Map) return out;
    raw.forEach((k, v) {
      final ccy = k.toString();
      if (!MoneySerializer.isSupported(ccy)) return;
      out[ccy] = MoneySerializer.fromSubunits(_asInt(v), ccy);
    });
    return out;
  }

  static Map<String, RecapExpenseRef> _parseBiggest(dynamic raw) {
    final out = <String, RecapExpenseRef>{};
    if (raw is! Map) return out;
    raw.forEach((k, v) {
      final ccy = k.toString();
      if (!MoneySerializer.isSupported(ccy) || v is! Map) return;
      final id = v['id'];
      final payer = v['payer'];
      if (id is! String || payer is! String) return;
      out[ccy] = (
        expenseId: id,
        amount: MoneySerializer.fromSubunits(_asInt(v['amt']), ccy),
        description: v['desc'] is String ? v['desc'] as String : null,
        categoryId: v['cat'] is String ? v['cat'] as String : null,
        payerId: payer,
      );
    });
    return out;
  }

  static Map<String, List<RecapPersonAmount>> _parsePersonAmounts(
      dynamic raw, String idKey) {
    final out = <String, List<RecapPersonAmount>>{};
    if (raw is! Map) return out;
    raw.forEach((k, v) {
      final ccy = k.toString();
      if (!MoneySerializer.isSupported(ccy) || v is! List) return;
      final list = <RecapPersonAmount>[];
      for (final e in v) {
        if (e is! Map) continue;
        final id = e[idKey];
        if (id is! String) continue;
        list.add((
          participantId: id,
          amount: MoneySerializer.fromSubunits(_asInt(e['amt']), ccy),
        ));
      }
      out[ccy] = List.unmodifiable(list);
    });
    return out;
  }

  static Map<String, List<RecapCategoryTotal>> _parseCategoryTotals(dynamic raw) {
    final out = <String, List<RecapCategoryTotal>>{};
    if (raw is! Map) return out;
    raw.forEach((k, v) {
      final ccy = k.toString();
      if (!MoneySerializer.isSupported(ccy) || v is! List) return;
      final list = <RecapCategoryTotal>[];
      for (final e in v) {
        if (e is! Map) continue;
        final cat = e['cat'];
        if (cat is! String) continue;
        list.add((
          categoryId: cat,
          total: MoneySerializer.fromSubunits(_asInt(e['amt']), ccy),
        ));
      }
      out[ccy] = List.unmodifiable(list);
    });
    return out;
  }

  static Map<String, Map<String, Decimal>> _parseOwed(dynamic raw) {
    final out = <String, Map<String, Decimal>>{};
    if (raw is! Map) return out;
    raw.forEach((k, v) {
      final ccy = k.toString();
      if (!MoneySerializer.isSupported(ccy) || v is! Map) return;
      final m = <String, Decimal>{};
      v.forEach((pk, pv) {
        m[pk.toString()] = MoneySerializer.fromSubunits(_asInt(pv), ccy);
      });
      out[ccy] = m;
    });
    return out;
  }
}
