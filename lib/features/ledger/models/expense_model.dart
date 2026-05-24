import 'package:decimal/decimal.dart';

import '../../../core/models/split_mode.dart';
import '../../../core/services/money_serializer.dart';

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
  final String? receiptUrl; // URL to receipt image in storage
  final DateTime createdAt;
  final String? categoryId;
  final String? note;

  /// Auth UID of the user who created this record. Stamped at create time
  /// and immutable thereafter — Firestore rules reject updates from any
  /// other UID. Empty string means "unknown" (legacy / test-only data).
  final String createdBy;

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
    final currency = data['currency'] as String? ?? 'OMR';
    final amountFils = data['amountFils'] as int? ?? 0;

    List<String>? customSplit;
    if (data['customSplitParticipants'] != null) {
      final rawList = data['customSplitParticipants'];
      if (rawList is List) {
        customSplit = List<String>.from(rawList);
      }
    }
    final splitMode = _splitModeFromPersisted(data['splitMode']);

    return Expense(
      id: data['id'] as String,
      tripId: data['eventId'] as String,
      payerParticipantId: data['payerParticipantId'] as String,
      amount: MoneySerializer.fromSubunits(amountFils, currency),
      currency: currency,
      description: data['description'] as String?,
      scope: ExpenseScope.fromString(data['scope'] as String? ?? 'global'),
      subGroupId: data['subGroupId'] as String?,
      customSplitParticipants: customSplit,
      splitMode: splitMode,
      splitDistribution: _splitDistributionFromPersisted(
        data['splitDistribution'],
        splitMode,
        currency,
      ),
      receiptUrl: data['receiptUrl'] as String?,
      createdAt: DateTime.parse(data['createdAt'] as String),
      categoryId: data['categoryId'] as String?,
      note: data['note'] as String?,
      isDeleted: data['isDeleted'] as bool? ?? false,
      deletedAt: data['deletedAt'] != null
          ? DateTime.parse(data['deletedAt'] as String)
          : null,
      createdBy: data['createdBy'] as String? ?? '',
    );
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
      'receiptUrl': receiptUrl,
      'createdAt': createdAt.toIso8601String(),
      'categoryId': categoryId,
      'note': note,
      'isDeleted': isDeleted,
      'deletedAt': deletedAt?.toIso8601String(),
      'createdBy': createdBy,
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
    final persistedValue =
        parsePersistedSubunit(value, field: 'splitDistribution');
    return switch (mode) {
      SplitMode.exact => MoneySerializer.fromSubunits(persistedValue, currency),
      SplitMode.percent =>
        (Decimal.fromInt(persistedValue) / Decimal.fromInt(1000)).toDecimal(
          scaleOnInfinitePrecision: 3,
        ),
      SplitMode.shares || SplitMode.equally => Decimal.fromInt(persistedValue),
    };
  }
}

/// Parse a persisted money/share value that *must* represent an integer
/// count of subunits, into an int. Throws [StateError] on any fractional
/// input. Accepts [int], [Decimal], [num], or a stringified [Decimal] for
/// Firestore round-trip flexibility.
///
/// Use this at every cache/Firestore read boundary instead of an ad-hoc
/// `.toInt()` cast: a doc that ever roundtrips a money column as a
/// fractional double (`9.99` instead of integer fils `999`) would otherwise
/// silently truncate to `9`, corrupting money math with no signal.
int parsePersistedSubunit(Object? value, {required String field}) {
  if (value is int) return value;
  if (value == null) {
    throw StateError('Expected integer subunits for $field, got null');
  }
  final asDecimal = value is Decimal
      ? value
      : Decimal.parse(value.toString());
  final asInt = asDecimal.toBigInt().toInt();
  if (Decimal.fromInt(asInt) != asDecimal) {
    throw StateError(
      'Expected integer subunits for $field, got fractional value: $value',
    );
  }
  return asInt;
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
