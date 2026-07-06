import 'package:decimal/decimal.dart';

import '../../../core/models/split_mode.dart';
import '../../../core/services/money_serializer.dart';
import 'split_explanation.dart';

/// Expense scope determines who shares the cost
enum ExpenseScope {
  global('global'),
  subGroup('sub_group'),
  personal('personal'),
  custom('custom');

  final String value;
  const ExpenseScope(this.value);

  static ExpenseScope fromString(String value) {
    return ExpenseScope.values.firstWhere(
      (scope) => scope.value == value,
      orElse: () => ExpenseScope.global,
    );
  }
}

/// Expense model for trip expenses
class Expense {
  final String id;
  final String tripId;
  final String payerParticipantId;
  final Decimal amount;
  final String? description;
  final ExpenseScope scope;
  final String? subGroupId;
  final List<String>?
  customSplitParticipants; // Participant IDs for custom scope
  final SplitMode? splitMode;
  final Map<String, Decimal>? splitDistribution;

  /// Opaque display-only metadata for an itemized split (#203). Reconstructs
  /// the itemized editor on reopen; NEVER feeds balance math (truth is
  /// [splitDistribution], persisted as `SplitMode.exact`). Null for every
  /// non-itemized expense — and [toFirestore] OMITS the key when null (a null
  /// value fails the `is map` rules bound).
  final SplitExplanation? splitExplanation;
  final String? receiptUrl; // URL to receipt image in storage
  final DateTime createdAt;
  final String? categoryId;
  final String? note;

  /// Auth UID of the user who created this record. Stamped at create time
  /// and immutable thereafter — Firestore rules reject updates from any
  /// other UID. Empty string means "unknown" (legacy / test-only data).
  final String createdBy;

  /// Auth UID of the user who last wrote this record (create or edit).
  /// Client-stamped on every write; Firestore rules pin it to the caller's
  /// UID whenever the write touches it. Read by the server audit-log trigger
  /// (#248, PR 2). Empty string means "unknown" (legacy docs predating this
  /// field) — the trigger falls back to [createdBy].
  final String lastEditedBy;

  // Category info
  final String? categoryName;
  final String? categoryIcon;

  // Payer profile info
  final String? payerName;
  final String? payerAvatarUrl;

  // Soft delete support
  final bool isDeleted;
  final DateTime? deletedAt;

  // Currency for this expense (ISO 4217 code, e.g. 'OMR', 'USD')
  final String _currency;

  const Expense({
    required this.id,
    required this.tripId,
    required this.payerParticipantId,
    required this.amount,
    this.description,
    required this.scope,
    this.subGroupId,
    this.customSplitParticipants,
    this.splitMode,
    this.splitDistribution,
    this.splitExplanation,
    this.receiptUrl,
    required this.createdAt,
    this.categoryId,
    this.note,
    this.categoryName,
    this.categoryIcon,
    this.payerName,
    this.payerAvatarUrl,
    this.isDeleted = false,
    this.deletedAt,
    this.createdBy = '',
    this.lastEditedBy = '',
    String currency = 'OMR',
  }) : _currency = currency;

  factory Expense.fromJson(Map<String, dynamic> json) {
    final category = json['expense_categories'] as Map<String, dynamic>?;
    final participant = json['participants'] as Map<String, dynamic>?;
    final profiles = participant?['profiles'] as Map<String, dynamic>?;

    // Parse custom_split_participants from Postgres array
    List<String>? customSplit;
    if (json['custom_split_participants'] != null) {
      final rawList = json['custom_split_participants'];
      if (rawList is List) {
        customSplit = rawList.cast<String>();
      }
    }
    final splitMode = _splitModeFromPersisted(json['split_mode']);

    return Expense(
      id: json['id'] as String,
      tripId: json['trip_id'] as String,
      payerParticipantId:
          json['payer_participant_id'] as String? ?? json['payer_id'] as String,
      amount: Decimal.parse(json['amount'].toString()),
      description: json['description'] as String?,
      scope: ExpenseScope.fromString(json['scope'] as String? ?? 'global'),
      subGroupId: json['sub_group_id'] as String?,
      customSplitParticipants: customSplit,
      splitMode: splitMode,
      splitDistribution: _splitDistributionFromPersisted(
        json['split_distribution'],
        splitMode,
        'OMR',
      ),
      receiptUrl: json['receipt_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      categoryId: json['category_id'] as String?,
      note: json['note'] as String?,
      categoryName: category?['name'] as String?,
      categoryIcon: category?['icon'] as String?,
      payerName:
          participant?['display_name'] as String? ??
          profiles?['display_name'] as String?,
      payerAvatarUrl: profiles?['avatar_url'] as String?,
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
      'amount': amount.toString(),
      'description': description,
      'scope': scope.value,
      'sub_group_id': subGroupId,
      'custom_split_participants': customSplitParticipants,
      if (splitMode != null) ...{
        'split_mode': splitMode!.storageKey,
        'split_distribution': _splitDistributionToPersisted(),
      },
      'receipt_url': receiptUrl,
      'category_id': categoryId,
      'note': note,
    };
  }

  /// Deserialize an [Expense] from a Firestore document map.
  ///
  /// Field names are camelCase.
  /// [tripId] maps to Firestore field `eventId` for backward compatibility
  /// with BalanceCalculator and UI code that passes `trip.id`.
  /// Money is stored as integer fils via [MoneySerializer].
  factory Expense.fromFirestore(Map<String, dynamic> data) {
    // TOTAL-PARSE money factory (#928): every present-but-wrong-type field is
    // salvaged to the value the TS server oracle `recomputeNet`
    // (functions/src/callables/groupNetBalance.ts) reads for the SAME doc —
    // never thrown. One malformed doc must not blank the ledger, the home
    // once-path, or the settle-up stream. The layer-2 skip-fence has NO server
    // counterpart for money docs (the oracle is total and drops nothing), so
    // this factory's totality is the real invariant — a new field added here
    // WITHOUT a salvage fallback would convert its throw into a silent
    // home-balance divergence. `malformed_doc_fencing_test.dart` test 7 pins it.
    //
    // Currency: type-gate THEN isSupported, mirroring the oracle `currencyOf`
    // (groupNetBalance.ts:52-54) — a non-string/unsupported code decodes at OMR.
    // The single fenced currency feeds the amount, the retained currency, and
    // the exact-split values (every MoneySerializer throw site). (#47/#193/#515)
    final rawCurrency =
        data['currency'] is String ? data['currency'] as String : 'OMR';
    final currency =
        MoneySerializer.isSupported(rawCurrency) ? rawCurrency : 'OMR';
    // amountFils: oracle `amountFilsOf` reads a non-number as 0
    // (groupNetBalance.ts:293-295). A rules-valid create pins positiveInt, so
    // only an Admin/legacy/forged doc reaches this 0 fallback.
    final amountFils = data['amountFils'] is int ? data['amountFils'] as int : 0;

    List<String>? customSplit;
    final rawList = data['customSplitParticipants'];
    if (rawList is List) {
      // Mirror the oracle `stringArray` filter (groupNetBalance.ts:329-331):
      // drop non-string elements rather than throw on `List<String>.from`.
      customSplit = rawList.whereType<String>().toList();
    }
    final splitMode = _splitModeFromPersisted(data['splitMode']);

    return Expense(
      id: data['id'] is String ? data['id'] as String : '',
      tripId: data['eventId'] is String ? data['eventId'] as String : '',
      payerParticipantId: data['payerParticipantId'] is String
          ? data['payerParticipantId'] as String
          : '',
      amount: MoneySerializer.fromSubunits(amountFils, currency),
      currency: currency,
      description:
          data['description'] is String ? data['description'] as String : null,
      scope: ExpenseScope.fromString(
        data['scope'] is String ? data['scope'] as String : 'global',
      ),
      subGroupId:
          data['subGroupId'] is String ? data['subGroupId'] as String : null,
      customSplitParticipants: customSplit,
      splitMode: splitMode,
      splitDistribution: _splitDistributionFromPersisted(
        data['splitDistribution'],
        splitMode,
        currency,
      ),
      splitExplanation:
          _splitExplanationFromPersisted(data['splitExplanation']),
      receiptUrl:
          data['receiptUrl'] is String ? data['receiptUrl'] as String : null,
      // The oracle never reads createdAt; a garbage value salvages to the epoch
      // UTC card at the list end (honest), never a throw. tryParse covers an
      // un-parseable STRING too.
      createdAt: (data['createdAt'] is String
              ? DateTime.tryParse(data['createdAt'] as String)
              : null) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      categoryId:
          data['categoryId'] is String ? data['categoryId'] as String : null,
      note: data['note'] is String ? data['note'] as String : null,
      isDeleted: data['isDeleted'] is bool ? data['isDeleted'] as bool : false,
      deletedAt: data['deletedAt'] is String
          ? DateTime.tryParse(data['deletedAt'] as String)
          : null,
      createdBy:
          data['createdBy'] is String ? data['createdBy'] as String : '',
      lastEditedBy: data['lastEditedBy'] is String
          ? data['lastEditedBy'] as String
          : '',
    );
  }

  /// Salvage the opaque itemized [SplitExplanation] map (#928). It is
  /// display-only and NEVER read by any Function/oracle, so a non-map value — or
  /// a map its own [SplitExplanation.fromMap] rejects — degrades to null rather
  /// than throwing the whole ledger stream.
  static SplitExplanation? _splitExplanationFromPersisted(Object? raw) {
    if (raw is! Map) return null;
    try {
      return SplitExplanation.fromMap(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }

  /// Serialize this [Expense] to a Firestore document map.
  ///
  /// Field names are camelCase. Money is stored as integer fils via
  /// [MoneySerializer]. Legacy join artifacts (payerName, categoryName,
  /// categoryIcon) are intentionally excluded -- they are read-time join
  /// artifacts that do not belong in Firestore.
  Map<String, dynamic> toFirestore() {
    final currency = this.currency;
    return {
      'id': id,
      'eventId': tripId,
      'payerParticipantId': payerParticipantId,
      'amountFils': MoneySerializer.toSubunits(amount, currency),
      'currency': currency,
      'description': description,
      'scope': scope.value,
      'subGroupId': subGroupId,
      'customSplitParticipants': customSplitParticipants ?? [],
      if (splitMode != null) ...{
        'splitMode': splitMode!.storageKey,
        'splitDistribution': _splitDistributionToPersisted(),
      },
      // #203 — write only when present: a null value fails the `is map` rules
      // bound (splitExplanationBounded). Top-level field, NOT nested in the
      // splitMode gate (which is omitted for an `equally` split).
      if (splitExplanation != null) 'splitExplanation': splitExplanation!.toMap(),
      'receiptUrl': receiptUrl,
      'createdAt': createdAt.toIso8601String(),
      'categoryId': categoryId,
      'note': note,
      'isDeleted': isDeleted,
      'deletedAt': deletedAt?.toIso8601String(),
      'createdBy': createdBy,
      'lastEditedBy': lastEditedBy,
    };
  }

  /// The currency for this expense (ISO 4217 code).
  ///
  /// Read from Firestore data. Defaults to 'OMR' (Omani Rial) when absent.
  String get currency => _currency;

  /// Alias for receiptUrl for backward compatibility
  String? get receiptPath => receiptUrl;

  Expense copyWith({
    String? id,
    String? tripId,
    String? payerParticipantId,
    Decimal? amount,
    String? currency,
    String? description,
    ExpenseScope? scope,
    String? subGroupId,
    List<String>? customSplitParticipants,
    SplitMode? splitMode,
    Map<String, Decimal>? splitDistribution,
    SplitExplanation? splitExplanation,
    String? receiptUrl,
    DateTime? createdAt,
    String? categoryId,
    String? note,
    String? categoryName,
    String? categoryIcon,
    String? payerName,
    String? payerAvatarUrl,
    bool? isDeleted,
    DateTime? deletedAt,
    String? createdBy,
    String? lastEditedBy,
    bool clearSplit = false,
  }) {
    return Expense(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      payerParticipantId: payerParticipantId ?? this.payerParticipantId,
      amount: amount ?? this.amount,
      currency: currency ?? _currency,
      description: description ?? this.description,
      scope: scope ?? this.scope,
      subGroupId: subGroupId ?? this.subGroupId,
      customSplitParticipants:
          customSplitParticipants ?? this.customSplitParticipants,
      splitMode: clearSplit ? null : splitMode ?? this.splitMode,
      splitDistribution: clearSplit
          ? null
          : splitDistribution ?? this.splitDistribution,
      // clearSplit reverts to a plain equal split, so it also drops itemized
      // metadata — never leave orphaned splitExplanation on a non-exact expense.
      splitExplanation: clearSplit
          ? null
          : splitExplanation ?? this.splitExplanation,
      receiptUrl: receiptUrl ?? this.receiptUrl,
      createdAt: createdAt ?? this.createdAt,
      categoryId: categoryId ?? this.categoryId,
      note: note ?? this.note,
      categoryName: categoryName ?? this.categoryName,
      categoryIcon: categoryIcon ?? this.categoryIcon,
      payerName: payerName ?? this.payerName,
      payerAvatarUrl: payerAvatarUrl ?? this.payerAvatarUrl,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      createdBy: createdBy ?? this.createdBy,
      lastEditedBy: lastEditedBy ?? this.lastEditedBy,
    );
  }

  Map<String, int>? _splitDistributionToPersisted() {
    final mode = splitMode;
    final distribution = splitDistribution;
    if (mode == null || distribution == null) return null;

    return {
      for (final entry in distribution.entries)
        entry.key: _splitValueToPersisted(entry.value, mode, currency),
    };
  }

  static SplitMode? _splitModeFromPersisted(Object? raw) {
    if (raw == null) return null;
    return splitModeFromStorage(raw.toString());
  }

  static Map<String, Decimal>? _splitDistributionFromPersisted(
    Object? raw,
    SplitMode? mode,
    String currency,
  ) {
    if (raw == null || mode == null || raw is! Map) return null;

    final distribution = <String, Decimal>{};
    for (final entry in raw.entries) {
      distribution[entry.key.toString()] = _splitValueFromPersisted(
        entry.value,
        mode,
        currency,
      );
    }
    return distribution.isEmpty ? null : distribution;
  }

  static int _splitValueToPersisted(
    Decimal value,
    SplitMode mode,
    String currency,
  ) {
    return switch (mode) {
      SplitMode.exact => MoneySerializer.toSubunits(value, currency),
      SplitMode.percent => (value * Decimal.fromInt(1000)).toBigInt().toInt(),
      SplitMode.shares || SplitMode.equally => value.toBigInt().toInt(),
    };
  }

  static Decimal _splitValueFromPersisted(
    Object? value,
    SplitMode mode,
    String currency,
  ) {
    final persistedValue = _persistedInt(value);
    return switch (mode) {
      SplitMode.exact => MoneySerializer.fromSubunits(persistedValue, currency),
      SplitMode.percent =>
        (Decimal.fromInt(persistedValue) / Decimal.fromInt(1000)).toDecimal(
          scaleOnInfinitePrecision: 3,
        ),
      SplitMode.shares || SplitMode.equally => Decimal.fromInt(persistedValue),
    };
  }

  static int _persistedInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is Decimal) return value.toBigInt().toInt();
    // #928: mirror the oracle `persistedInt` (groupNetBalance.ts:86-93) — a
    // non-numeric string (or any other type) reads as 0, never throws.
    return Decimal.tryParse(value.toString())?.toBigInt().toInt() ?? 0;
  }
}

/// Balance summary for a user
class UserBalance {
  final String participantId;
  final String? displayName;
  final Decimal totalPaid;
  final Decimal totalOwed;
  final Decimal netBalance; // positive = owed money, negative = owes money

  const UserBalance({
    required this.participantId,
    this.displayName,
    required this.totalPaid,
    required this.totalOwed,
    required this.netBalance,
  });

  /// User owes money to the group
  bool get owesMoney => netBalance < Decimal.zero;

  /// User is owed money by the group
  bool get isOwedMoney => netBalance > Decimal.zero;

  /// User is settled (balance is zero or near zero)
  bool get isSettled => netBalance.abs() < Decimal.parse('0.001');
}
