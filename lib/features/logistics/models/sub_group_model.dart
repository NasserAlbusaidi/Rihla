/// Sub-group model for cars, rooms, and teams
class SubGroup {
  final String id;
  final String tripId;
  final String name;
  final SubGroupType type;
  final int capacity;
  final DateTime? createdAt;
  final List<SubGroupMember> members;

  const SubGroup({
    required this.id,
    required this.tripId,
    required this.name,
    required this.type,
    this.capacity = 4,
    this.createdAt,
    this.members = const [],
  });

  factory SubGroup.fromJson(Map<String, dynamic> json) {
    final membersList = json['sub_group_members'] as List<dynamic>?;

    return SubGroup(
      id: json['id'] as String,
      tripId: json['trip_id'] as String,
      name: json['name'] as String,
      type: SubGroupType.fromValue(json['type'] as String? ?? 'CAR'),
      capacity: json['capacity'] as int? ?? 4,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      members:
          membersList
              ?.map((m) => SubGroupMember.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'trip_id': tripId,
      'name': name,
      'type': type.value,
      'capacity': capacity,
    };
  }

  int get memberCount => members.length;
  bool get isFull => memberCount >= capacity;
  double get fillPercentage => (memberCount / capacity).clamp(0.0, 1.0);

  SubGroup copyWith({
    String? id,
    String? tripId,
    String? name,
    SubGroupType? type,
    int? capacity,
    DateTime? createdAt,
    List<SubGroupMember>? members,
  }) {
    return SubGroup(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      name: name ?? this.name,
      type: type ?? this.type,
      capacity: capacity ?? this.capacity,
      createdAt: createdAt ?? this.createdAt,
      members: members ?? this.members,
    );
  }
}

/// Sub-group member with user profile info
class SubGroupMember {
  final String id;
  final String subGroupId;
  final String participantId;
  final DateTime? joinedAt;
  final String? displayName;
  final String? avatarUrl;

  const SubGroupMember({
    required this.id,
    required this.subGroupId,
    required this.participantId,
    this.joinedAt,
    this.displayName,
    this.avatarUrl,
  });

  factory SubGroupMember.fromJson(Map<String, dynamic> json) {
    // Handle nested join from participants table
    final participant = json['participants'] as Map<String, dynamic>?;
    final profiles =
        (participant?['profiles'] as Map<String, dynamic>?) ??
        (json['profiles'] as Map<String, dynamic>?);

    return SubGroupMember(
      id: json['id'] as String,
      subGroupId: json['sub_group_id'] as String,
      participantId:
          json['participant_id'] as String? ?? json['user_id'] as String,
      joinedAt: json['joined_at'] != null
          ? DateTime.parse(json['joined_at'] as String)
          : null,
      displayName:
          (participant?['display_name'] as String?) ??
          (profiles?['display_name'] as String?),
      avatarUrl: profiles?['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sub_group_id': subGroupId,
      'participant_id': participantId,
    };
  }

  String get initials {
    if (displayName != null && displayName!.isNotEmpty) {
      final parts = displayName!.split(' ');
      if (parts.length >= 2) {
        return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      }
      return displayName![0].toUpperCase();
    }
    return 'U';
  }
}

/// Sub-group type enum
enum SubGroupType {
  car('CAR'),
  room('ROOM'),
  team('TEAM');

  final String value;
  const SubGroupType(this.value);

  static SubGroupType fromValue(String value) {
    return SubGroupType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => SubGroupType.car,
    );
  }

  String get displayName {
    switch (this) {
      case SubGroupType.car:
        return 'Car';
      case SubGroupType.room:
        return 'Room';
      case SubGroupType.team:
        return 'Team';
    }
  }

  String get pluralName {
    switch (this) {
      case SubGroupType.car:
        return 'Cars';
      case SubGroupType.room:
        return 'Rooms';
      case SubGroupType.team:
        return 'Teams';
    }
  }
}
