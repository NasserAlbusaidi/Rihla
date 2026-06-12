import 'package:decimal/decimal.dart';

/// The server-maintained per-group balance aggregate (#366; v2 per-currency
/// buckets #382 PR-3).
///
/// Decoded from `groups/{gid}/aggregates/balance`, which the
/// `balanceAggregator` Cloud Function triggers keep fresh by re-running the
/// shared `groupNetBalance` oracle on every money/membership write (spec:
/// `docs/plans/2026-06-12-382-pr3-aggregate-v2.md` D1/D2). This is a DISPLAY
/// CACHE for the home dashboard only — it must never feed a write path; all
/// settle-up surfaces and server gates compute live.
///
/// NON-DECOMPOSITION (per bucket): [netByCurrency] is NOT the sum of
/// [perEventNetByCurrency] slices. The drill-down universe is
/// `event.participantIds` only (former financial actors appear in net, never
/// in a slice), group-scope settlements fold into net only, and
/// out-of-universe drops differ. Never reconcile one from the other.
class GroupBalanceAggregate {
  const GroupBalanceAggregate({
    required this.netByCurrency,
    required this.perEventNetByCurrency,
    required this.eventCount,
    required this.currency,
  });

  /// ccy → uid → group net (settlement-folded, full balance universe). A uid
  /// absent from a bucket has net zero in that currency — use [netFor].
  final Map<String, Map<String, Decimal>> netByCurrency;

  /// eventId → ccy → uid → event-scoped net (the journey-ticket drill-down
  /// slice, mirroring the client `_buildPerEventBreakdown` contract).
  final Map<String, Map<String, Map<String, Decimal>>> perEventNetByCurrency;

  /// Count of live events in the group.
  final int eventCount;

  /// The group's default currency at compute time (diagnostics only).
  final String currency;

  /// ccy → net for [uid], mirroring the bucket key-set: zero when the uid is
  /// absent from a bucket.
  Map<String, Decimal> netFor(String uid) {
    return {
      for (final entry in netByCurrency.entries)
        entry.key: entry.value[uid] ?? Decimal.zero,
    };
  }

  /// eventId → ccy → net for [uid]. A ccy entry is OMITTED when the uid is
  /// absent from that bucket (the v1 containsKey semantics); events with no
  /// remaining ccy entries are omitted entirely.
  Map<String, Map<String, Decimal>> perEventNetFor(String uid) {
    final out = <String, Map<String, Decimal>>{};
    for (final event in perEventNetByCurrency.entries) {
      final slices = <String, Decimal>{
        for (final bucket in event.value.entries)
          if (bucket.value.containsKey(uid)) bucket.key: bucket.value[uid]!,
      };
      if (slices.isNotEmpty) out[event.key] = slices;
    }
    return out;
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

  static Map<String, Map<String, Decimal>>? _decodeBucketedMilliMap(
    Object? raw,
  ) {
    if (raw is! Map) return null;
    final out = <String, Map<String, Decimal>>{};
    for (final entry in raw.entries) {
      final ccy = entry.key;
      if (ccy is! String) return null;
      final bucket = _decodeMilliMap(entry.value);
      if (bucket == null) return null;
      out[ccy] = bucket;
    }
    return out;
  }

  /// Decodes the aggregate doc. Returns null — treat as "no aggregate, fall
  /// back to the client compute" — for missing/degraded docs, v1 or unknown
  /// future schema versions, or malformed field shapes. Never throws on
  /// Firestore data.
  static GroupBalanceAggregate? fromDoc(Map<String, dynamic>? data) {
    if (data == null) return null;
    if (data['schemaVersion'] != 2) return null;
    if (data['degraded'] == true) return null;

    final netByCurrency = _decodeBucketedMilliMap(data['netMilliByCurrency']);
    if (netByCurrency == null) return null;

    final rawPerEvent = data['perEventNetMilliByCurrency'];
    if (rawPerEvent is! Map) return null;
    final perEventNetByCurrency = <String, Map<String, Map<String, Decimal>>>{};
    for (final entry in rawPerEvent.entries) {
      final eventId = entry.key;
      if (eventId is! String) return null;
      final slices = _decodeBucketedMilliMap(entry.value);
      if (slices == null) return null;
      perEventNetByCurrency[eventId] = slices;
    }

    final eventCount = data['eventCount'];
    if (eventCount is! int) return null;

    final currency = data['currency'];
    if (currency is! String || currency.isEmpty) return null;

    return GroupBalanceAggregate(
      netByCurrency: netByCurrency,
      perEventNetByCurrency: perEventNetByCurrency,
      eventCount: eventCount,
      currency: currency,
    );
  }
}
