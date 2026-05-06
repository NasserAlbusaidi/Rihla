class ActivityLog {
  final String id;
  final String tripId;
  final String? actorId;
  final String? targetParticipantId;
  final String category; // MONEY, GEAR, DOCS
  final String eventType; // CREATE, UPDATE, DELETE
  final String logText;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final String? actorName;
  final String? actorAvatar;

  const ActivityLog({
    required this.id,
    required this.tripId,
    this.actorId,
    this.targetParticipantId,
    required this.category,
    required this.eventType,
    required this.logText,
    this.metadata = const {},
    required this.createdAt,
    this.actorName,
    this.actorAvatar,
  });

  factory ActivityLog.fromJson(Map<String, dynamic> json) {
    final actorDisplayName = json['actor']?['display_name'] as String?;
    var logText = json['log_text'] as String;

    // Replace generic placeholders with actual actor name when available
    if (actorDisplayName != null && actorDisplayName.isNotEmpty) {
      logText = logText
          .replaceFirst('Someone paid', '$actorDisplayName paid')
          .replaceFirst('Someone made', '$actorDisplayName made')
          .replaceFirst('user paid', '$actorDisplayName paid')
          .replaceFirst('User paid', '$actorDisplayName paid')
          .replaceFirst('user made', '$actorDisplayName made')
          .replaceFirst('User made', '$actorDisplayName made');
    }

    return ActivityLog(
      id: json['id'] as String,
      tripId: json['trip_id'] as String,
      actorId: json['actor_id'] as String?,
      targetParticipantId: json['target_participant_id'] as String?,
      category: json['category'] as String,
      eventType: json['event_type'] as String,
      logText: logText,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      createdAt: DateTime.parse(json['created_at'] as String),
      actorName: actorDisplayName,
      actorAvatar: json['actor']?['avatar_url'] as String?,
    );
  }

  bool get isDelete => eventType == 'DELETE';
  bool get isUpdate => eventType == 'UPDATE';
  bool get isCreate => eventType == 'CREATE';

  /// Deserialize an [ActivityLog] from a Firestore document map.
  ///
  /// Field names are camelCase. [tripId] maps to `eventId` for backward
  /// compatibility.
  factory ActivityLog.fromFirestore(Map<String, dynamic> data) {
    return ActivityLog(
      id: data['id'] as String,
      tripId: data['eventId'] as String,
      actorId: data['actorId'] as String?,
      targetParticipantId: data['targetParticipantId'] as String?,
      category: data['category'] as String,
      eventType: data['eventType'] as String,
      logText: data['logText'] as String,
      metadata: (data['metadata'] as Map<String, dynamic>?) ?? const {},
      createdAt: DateTime.parse(data['createdAt'] as String),
      actorName: data['actorName'] as String?,
      actorAvatar: data['actorAvatar'] as String?,
    );
  }

  /// Serialize this [ActivityLog] to a Firestore document map.
  ///
  /// Field names are camelCase.
  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'eventId': tripId,
      'actorId': actorId,
      'targetParticipantId': targetParticipantId,
      'category': category,
      'eventType': eventType,
      'logText': logText,
      'metadata': metadata,
      'createdAt': createdAt.toIso8601String(),
      'actorName': actorName,
    };
  }
}
