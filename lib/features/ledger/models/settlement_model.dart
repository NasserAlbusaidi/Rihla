import 'package:decimal/decimal.dart';

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
}
