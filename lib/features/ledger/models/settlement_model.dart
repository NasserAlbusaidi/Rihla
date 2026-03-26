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
    final currency = data['currency'] as String? ?? 'OMR';
    final amountFils = data['amountFils'] as int? ?? 0;

    return Settlement(
      id: data['id'] as String,
      tripId: data['eventId'] as String,
      payerParticipantId: data['payerParticipantId'] as String?,
      recipientParticipantId: data['recipientParticipantId'] as String?,
      amount: MoneySerializer.fromSubunits(amountFils, currency),
      note: data['note'] as String?,
      settledAt: DateTime.parse(data['settledAt'] as String),
      isDeleted: data['isDeleted'] as bool? ?? false,
      deletedAt: data['deletedAt'] != null
          ? DateTime.parse(data['deletedAt'] as String)
          : null,
    );
  }

  /// Serialize this [Settlement] to a Firestore document map.
  ///
  /// Field names are camelCase. Money is stored as integer fils.
  Map<String, dynamic> toFirestore() {
    const currency = 'OMR';
    return {
      'id': id,
      'eventId': tripId,
      'payerParticipantId': payerParticipantId,
      'recipientParticipantId': recipientParticipantId,
      'amountFils': MoneySerializer.toSubunits(amount, currency),
      'currency': currency,
      'note': note,
      'settledAt': settledAt.toIso8601String(),
      'isDeleted': isDeleted,
      'deletedAt': deletedAt?.toIso8601String(),
    };
  }
}
