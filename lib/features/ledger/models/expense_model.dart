import 'package:decimal/decimal.dart';

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
  final String? receiptUrl; // URL to receipt image in storage
  final DateTime createdAt;
  final String? categoryId;
  final String? note;

  // Category info
  final String? categoryName;
  final String? categoryIcon;

  // Payer profile info
  final String? payerName;
  final String? payerAvatarUrl;

  // Soft delete support
  final bool isDeleted;
  final DateTime? deletedAt;

  const Expense({
    required this.id,
    required this.tripId,
    required this.payerParticipantId,
    required this.amount,
    this.description,
    required this.scope,
    this.subGroupId,
    this.customSplitParticipants,
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
  });

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

    return Expense(
      id: data['id'] as String,
      tripId: data['eventId'] as String,
      payerParticipantId: data['payerParticipantId'] as String,
      amount: MoneySerializer.fromSubunits(amountFils, currency),
      description: data['description'] as String?,
      scope: ExpenseScope.fromString(data['scope'] as String? ?? 'global'),
      subGroupId: data['subGroupId'] as String?,
      customSplitParticipants: customSplit,
      receiptUrl: data['receiptUrl'] as String?,
      createdAt: DateTime.parse(data['createdAt'] as String),
      categoryId: data['categoryId'] as String?,
      note: data['note'] as String?,
      isDeleted: data['isDeleted'] as bool? ?? false,
      deletedAt: data['deletedAt'] != null
          ? DateTime.parse(data['deletedAt'] as String)
          : null,
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
      'receiptUrl': receiptUrl,
      'createdAt': createdAt.toIso8601String(),
      'categoryId': categoryId,
      'note': note,
      'isDeleted': isDeleted,
      'deletedAt': deletedAt?.toIso8601String(),
    };
  }

  /// The currency for this expense.
  ///
  /// Expenses default to OMR (Omani Rial). Use [copyWith] to change.
  String get currency => 'OMR';

  /// Alias for receiptUrl for backward compatibility
  String? get receiptPath => receiptUrl;

  Expense copyWith({
    String? id,
    String? tripId,
    String? payerParticipantId,
    Decimal? amount,
    String? description,
    ExpenseScope? scope,
    String? subGroupId,
    List<String>? customSplitParticipants,
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
  }) {
    return Expense(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      payerParticipantId: payerParticipantId ?? this.payerParticipantId,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      scope: scope ?? this.scope,
      subGroupId: subGroupId ?? this.subGroupId,
      customSplitParticipants:
          customSplitParticipants ?? this.customSplitParticipants,
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
    );
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
