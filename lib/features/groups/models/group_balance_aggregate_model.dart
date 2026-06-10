import 'package:decimal/decimal.dart';

/// The server-maintained per-group balance aggregate (#366).
///
/// Decoded from `groups/{gid}/aggregates/balance`, which the
/// `balanceAggregator` Cloud Function triggers keep fresh by re-running the
/// shared `groupNetBalance` oracle on every money/membership write (spec:
/// `docs/plans/2026-06-10-366-balance-aggregate.md` §0.3). This is a DISPLAY
/// CACHE for the home dashboard only — it must never feed a write path; all
/// settle-up surfaces and server gates compute live.
///
/// NON-DECOMPOSITION: [netByUid] is NOT the sum of [perEventNetByUid] slices.
/// The drill-down universe is `event.participantIds` only (former financial
/// actors appear in net, never in a slice), group-scope settlements fold into
/// net only, and out-of-universe drops differ. Never reconcile one from the
/// other.
class GroupBalanceAggregate {
  const GroupBalanceAggregate({
    required this.netByUid,
    required this.perEventNetByUid,
    required this.eventCount,
    required this.currency,
    required this.currencies,
  });

  /// Group net per uid (settlement-folded, full balance universe). A uid
  /// absent from the map has net zero — use [netFor].
  final Map<String, Decimal> netByUid;

  /// eventId → uid → event-scoped net (the journey-ticket drill-down slice,
  /// mirroring the client `_buildPerEventBreakdown` contract).
  final Map<String, Map<String, Decimal>> perEventNetByUid;

  /// Count of live events in the group.
  final int eventCount;

  /// The group's currency at compute time (immutable per rules).
  final String currency;

  /// Distinct EXPENSE currencies that contributed to the net (the oracle's
  /// #261 contract). More than one entry ⇒ legacy mixed-currency group — the
  /// flat net is not honest in a single currency and the facade must fall
  /// back to the client compute.
  final List<String> currencies;

  Decimal netFor(String uid) => netByUid[uid] ?? Decimal.zero;

  /// eventId → net for [uid], omitting events the uid has no slice in.
  Map<String, Decimal> perEventNetFor(String uid) {
    return {
      for (final entry in perEventNetByUid.entries)
        if (entry.value.containsKey(uid)) entry.key: entry.value[uid]!,
    };
  }

  static Decimal _fromMilli(int milli) =>
      (Decimal.fromInt(milli) / Decimal.fromInt(1000)).toDecimal();

  static Map<String, Decimal>? _decodeMilliMap(Object? raw) {
    if (raw is! Map) return null;
    final out = <String, Decimal>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      // A non-int milli entry is dropped (boundary validation: never trust
      // external data) — the remaining entries stay usable.
      if (key is String && value is int) {
        out[key] = _fromMilli(value);
      }
    }
    return out;
  }

  /// Decodes the aggregate doc. Returns null — treat as "no aggregate, fall
  /// back to the client compute" — for missing/degraded docs, unknown future
  /// schema versions, or malformed field shapes. Never throws on Firestore
  /// data.
  static GroupBalanceAggregate? fromDoc(Map<String, dynamic>? data) {
    if (data == null) return null;
    if (data['schemaVersion'] != 1) return null;
    if (data['degraded'] == true) return null;

    final netByUid = _decodeMilliMap(data['netMilli']);
    if (netByUid == null) return null;

    final rawPerEvent = data['perEventNetMilli'];
    if (rawPerEvent is! Map) return null;
    final perEventNetByUid = <String, Map<String, Decimal>>{};
    for (final entry in rawPerEvent.entries) {
      final eventId = entry.key;
      if (eventId is! String) return null;
      final slice = _decodeMilliMap(entry.value);
      if (slice == null) return null;
      perEventNetByUid[eventId] = slice;
    }

    final eventCount = data['eventCount'];
    if (eventCount is! int) return null;

    final currency = data['currency'];
    if (currency is! String || currency.isEmpty) return null;

    final rawCurrencies = data['currencies'];
    if (rawCurrencies is! List) return null;
    final currencies = rawCurrencies.whereType<String>().toList();

    return GroupBalanceAggregate(
      netByUid: netByUid,
      perEventNetByUid: perEventNetByUid,
      eventCount: eventCount,
      currency: currency,
      currencies: currencies,
    );
  }
}
