/// Gear item model for packing checklist
class GearItem {
  final String id;
  final String tripId;
  final String itemName;
  final String? assignedTo;
  final bool isPacked;
  final int sequenceId;
  final DateTime? createdAt;
  final String? assignedToName;
  final String? assignedToAvatar;
  final bool isDeleted;
  final DateTime? deletedAt;
  final bool isHighPriority;

  const GearItem({
    required this.id,
    required this.tripId,
    required this.itemName,
    this.assignedTo,
    this.isPacked = false,
    this.sequenceId = 0,
    this.createdAt,
    this.assignedToName,
    this.assignedToAvatar,
    this.isDeleted = false,
    this.deletedAt,
    this.isHighPriority = false,
  });

  factory GearItem.fromJson(Map<String, dynamic> json) {
    final profiles = json['profiles'] as Map<String, dynamic>?;

    return GearItem(
      id: json['id'] as String,
      tripId: json['trip_id'] as String,
      itemName: json['item_name'] as String,
      assignedTo: json['assigned_to'] as String?,
      isPacked: json['is_packed'] as bool? ?? false,
      sequenceId: json['sequence_id'] as int? ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      assignedToName: profiles?['display_name'] as String?,
      assignedToAvatar: profiles?['avatar_url'] as String?,
      isDeleted: json['is_deleted'] as bool? ?? false,
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
      isHighPriority: json['is_high_priority'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'trip_id': tripId,
      'item_name': itemName,
      'assigned_to': assignedTo,
      'is_packed': isPacked,
      'sequence_id': sequenceId,
      'is_high_priority': isHighPriority,
    };
  }

  /// Deserialize a [GearItem] from a Firestore document map.
  ///
  /// Field names are camelCase. [tripId] maps to `eventId` for backward
  /// compatibility. No money fields.
  factory GearItem.fromFirestore(Map<String, dynamic> data) {
    return GearItem(
      id: data['id'] as String,
      tripId: data['eventId'] as String,
      itemName: data['itemName'] as String,
      assignedTo: data['assignedTo'] as String?,
      isPacked: data['isPacked'] as bool? ?? false,
      sequenceId: data['sequenceId'] as int? ?? 0,
      isHighPriority: data['isHighPriority'] as bool? ?? false,
      isDeleted: data['isDeleted'] as bool? ?? false,
      deletedAt: data['deletedAt'] != null
          ? DateTime.parse(data['deletedAt'] as String)
          : null,
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'] as String)
          : null,
    );
  }

  /// Serialize this [GearItem] to a Firestore document map.
  ///
  /// Field names are camelCase. Legacy join artifacts (assignedToName,
  /// assignedToAvatar) are excluded.
  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'eventId': tripId,
      'itemName': itemName,
      'assignedTo': assignedTo,
      'isPacked': isPacked,
      'sequenceId': sequenceId,
      'isHighPriority': isHighPriority,
      'isDeleted': isDeleted,
      'deletedAt': deletedAt?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  GearItem copyWith({
    String? id,
    String? tripId,
    String? itemName,
    String? assignedTo,
    bool? isPacked,
    int? sequenceId,
    DateTime? createdAt,
    String? assignedToName,
    String? assignedToAvatar,
    bool? isDeleted,
    DateTime? deletedAt,
    bool? isHighPriority,
  }) {
    return GearItem(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      itemName: itemName ?? this.itemName,
      assignedTo: assignedTo ?? this.assignedTo,
      isPacked: isPacked ?? this.isPacked,
      sequenceId: sequenceId ?? this.sequenceId,
      createdAt: createdAt ?? this.createdAt,
      assignedToName: assignedToName ?? this.assignedToName,
      assignedToAvatar: assignedToAvatar ?? this.assignedToAvatar,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      isHighPriority: isHighPriority ?? this.isHighPriority,
    );
  }

  GearStatus get status {
    if (isPacked) return GearStatus.packed;
    if (assignedTo != null) return GearStatus.claimed;
    return GearStatus.unclaimed;
  }

  String get assigneeInitials {
    if (assignedToName != null && assignedToName!.isNotEmpty) {
      final parts = assignedToName!.split(' ');
      if (parts.length >= 2) {
        return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      }
      return assignedToName![0].toUpperCase();
    }
    return '?';
  }
}

/// Gear item status
enum GearStatus {
  unclaimed,
  claimed,
  packed;

  String get displayName {
    switch (this) {
      case GearStatus.unclaimed:
        return 'Unclaimed';
      case GearStatus.claimed:
        return 'Assigned';
      case GearStatus.packed:
        return 'Packed';
    }
  }
}
