import 'package:decimal/decimal.dart';

import '../../../core/services/money_serializer.dart';

class Settlement {
  final String id;
  final String tripId;
  final String? payerParticipantId;
  final String? recipientParticipantId;
  final Decimal amount;
  final String? note;
  final DateTime settledAt;
  final String? payerName;
  final String? recipientName;
  final bool isDeleted;
  final DateTime? deletedAt;

  /// Settlement scope: 'event' (default) or 'group'. Added per D-10.
  /// Existing event settlements have no scope field — they default to 'event'.
  final String scope;

  /// For group-scoped settlements, the group ID. Null for event settlements.
  /// Added per D-10.
  final String? groupId;

  /// Auth UID of the user who created this settlement record. Stamped at
  /// create time and immutable thereafter — Firestore rules reject updates
  /// from any other UID. Empty string means "unknown" (legacy / test-only).
  final String createdBy;

  /// The fence-validated currency [amount] was deserialized with (#382 PR-0,
  /// mirroring [Expense]). Always a supported code: unknown/missing falls back
  /// to OMR in [fromFirestore], so the label can never disagree with the scale.
  final String currency;

  /// Links this settlement to a group-level settle-up (#752). When a group
  /// transfer is decomposed into per-event settlement docs + a residual group
  /// doc, every doc of that one logical settle-up shares this id so the group
  /// history can surface them (and a fast-follow can correct them atomically).
  /// Null on legacy docs and on directly-recorded event settlements.
  final String? groupSettleUpId;

  /// The original settlement this row offsets (#889). Written ONLY by the
  /// server-authoritative `correctSettlement`/`correctLogicalSettleUp`
  /// callables (Admin SDK) — `firestore.rules` denies the key on any
  /// client-created settlement (hasOnly-omission), so its presence is
  /// un-forgeable proof of a server-written correction. Null on every normal
  /// payment and on legacy pre-#889 note-only corrections.
  final String? correctionOfSettlementId;

  /// True when [correctionOfSettlementId] is a non-blank marker (#889). The
  /// un-forgeable signal for write-affordance/idempotency decisions — prefer
  /// this over the legacy note-based `isCorrectionNote` for any NEW
  /// persistence/derived-surface decision (display stays note-based).
  bool get isMarkedCorrection =>
      correctionOfSettlementId != null &&
      correctionOfSettlementId!.trim().isNotEmpty;

  const Settlement({
    required this.id,
    required this.tripId,
    this.payerParticipantId,
    this.recipientParticipantId,
    required this.amount,
    this.note,
    required this.settledAt,
    this.payerName,
    this.recipientName,
    this.isDeleted = false,
    this.deletedAt,
    this.scope = 'event',
    this.groupId,
    this.createdBy = '',
    this.currency = 'OMR',
    this.groupSettleUpId,
    this.correctionOfSettlementId,
  });

  factory Settlement.fromJson(Map<String, dynamic> json) {
    final payer = json['payer_participant'] as Map<String, dynamic>?;
    final recipient = json['recipient_participant'] as Map<String, dynamic>?;
    final payerProfile = payer?['profiles'] as Map<String, dynamic>?;
    final recipientProfile = recipient?['profiles'] as Map<String, dynamic>?;

    return Settlement(
      id: json['id'] as String,
      tripId: json['trip_id'] as String,
      payerParticipantId:
          json['payer_participant_id'] as String? ??
          json['payer_id'] as String?,
      recipientParticipantId:
          json['recipient_participant_id'] as String? ??
          json['recipient_id'] as String?,
      amount: Decimal.parse(json['amount'].toString()),
      note: json['note'] as String?,
      settledAt: DateTime.parse(json['settled_at'] as String),
      payerName:
          payer?['display_name'] as String? ??
          payerProfile?['display_name'] as String?,
      recipientName:
          recipient?['display_name'] as String? ??
          recipientProfile?['display_name'] as String?,
      isDeleted: json['is_deleted'] as bool? ?? false,
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'trip_id': tripId,
      'payer_participant_id': payerParticipantId,
      'recipient_participant_id': recipientParticipantId,
      'amount': amount.toString(),
      'note': note,
      'settled_at': settledAt.toIso8601String(),
    };
  }

  /// Deserialize a [Settlement] from a Firestore document map.
  ///
  /// Field names are camelCase. [tripId] maps to `eventId` for backward
  /// compatibility. Money is stored as integer fils via [MoneySerializer].
  factory Settlement.fromFirestore(Map<String, dynamic> data) {
    // TOTAL-PARSE money factory (#928): every present-but-wrong-type field is
    // salvaged to the value the TS server oracle `recomputeNet`
    // (functions/src/callables/groupNetBalance.ts) reads for the SAME doc —
    // never thrown. One malformed settlement must not blank the settle-up stream
    // or the home once-path. The layer-2 skip-fence has NO server counterpart
    // for money docs (the oracle is total), so this factory's totality is the
    // real invariant — `malformed_doc_fencing_test.dart` test 7 pins it.
    //
    // Currency: type-gate THEN isSupported, mirroring the oracle `currencyOf`
    // (groupNetBalance.ts:52-54). (#47/#193/#220)
    final rawCurrency =
        data['currency'] is String ? data['currency'] as String : 'OMR';
    final currency = MoneySerializer.isSupported(rawCurrency)
        ? rawCurrency
        : 'OMR';
    // amountFils: oracle `amountFilsOf` reads a non-number as 0.
    final amountFils =
        data['amountFils'] is int ? data['amountFils'] as int : 0;
    final scope = data['scope'] is String ? data['scope'] as String : 'event';
    final groupId = data['groupId'] is String ? data['groupId'] as String : null;

    // For group settlements, eventId may not be set — fall back to groupId as
    // sentinel (per RESEARCH.md Pitfall 3). Event settlements always have eventId.
    final tripId =
        data['eventId'] is String ? data['eventId'] as String : (groupId ?? '');

    return Settlement(
      id: data['id'] is String ? data['id'] as String : '',
      tripId: tripId,
      payerParticipantId: data['payerParticipantId'] is String
          ? data['payerParticipantId'] as String
          : null,
      recipientParticipantId: data['recipientParticipantId'] is String
          ? data['recipientParticipantId'] as String
          : null,
      amount: MoneySerializer.fromSubunits(amountFils, currency),
      note: data['note'] is String ? data['note'] as String : null,
      // The oracle never reads settledAt (the issue's named repro); a garbage
      // value salvages to epoch UTC, never a throw. The doc's money keeps
      // counting.
      settledAt: (data['settledAt'] is String
              ? DateTime.tryParse(data['settledAt'] as String)
              : null) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      payerName:
          data['payerName'] is String ? data['payerName'] as String : null,
      recipientName: data['recipientName'] is String
          ? data['recipientName'] as String
          : null,
      isDeleted: data['isDeleted'] is bool ? data['isDeleted'] as bool : false,
      deletedAt: data['deletedAt'] is String
          ? DateTime.tryParse(data['deletedAt'] as String)
          : null,
      scope: scope,
      groupId: groupId,
      createdBy:
          data['createdBy'] is String ? data['createdBy'] as String : '',
      currency: currency,
      groupSettleUpId: data['groupSettleUpId'] is String
          ? data['groupSettleUpId'] as String
          : null,
      // #889: read as a string when present; any other type (or absence)
      // reads as null/non-marked rather than throwing — the marker is
      // Admin-only, but a forged/legacy doc must never error the stream.
      correctionOfSettlementId: data['correctionOfSettlementId'] is String
          ? data['correctionOfSettlementId'] as String
          : null,
    );
  }
}
