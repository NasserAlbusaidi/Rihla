/// Trip model representing a trip in Safar
class Trip {
  final String id;
  final String name;
  final String inviteCode;
  final String leaderId;
  final TripModules modules;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? startDate;
  final DateTime? endDate;
  final String icon; // airplane, car, camping, hiking, beach, mountain, ship

  const Trip({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.leaderId,
    required this.modules,
    required this.createdAt,
    this.updatedAt,
    this.startDate,
    this.endDate,
    this.icon = 'airplane',
  });

  /// Create Trip from Supabase JSON
  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json['id'] as String,
      name: json['name'] as String,
      inviteCode: json['invite_code'] as String,
      leaderId: json['leader_id'] as String,
      modules: TripModules.fromJson(
        json['modules'] as Map<String, dynamic>? ?? {},
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      startDate: json['start_date'] != null
          ? DateTime.parse(json['start_date'] as String)
          : null,
      endDate: json['end_date'] != null
          ? DateTime.parse(json['end_date'] as String)
          : null,
      icon: json['icon'] as String? ?? 'airplane',
    );
  }

  /// Convert Trip to JSON for Supabase
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'invite_code': inviteCode,
      'leader_id': leaderId,
      'modules': modules.toJson(),
      'icon': icon,
      'created_at': createdAt.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      if (startDate != null)
        'start_date': startDate!.toIso8601String().split('T').first,
      if (endDate != null)
        'end_date': endDate!.toIso8601String().split('T').first,
    };
  }

  /// Create a copy with updated fields
  Trip copyWith({
    String? id,
    String? name,
    String? inviteCode,
    String? leaderId,
    TripModules? modules,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? startDate,
    DateTime? endDate,
    String? icon,
  }) {
    return Trip(
      id: id ?? this.id,
      name: name ?? this.name,
      inviteCode: inviteCode ?? this.inviteCode,
      leaderId: leaderId ?? this.leaderId,
      modules: modules ?? this.modules,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      icon: icon ?? this.icon,
    );
  }

  /// Get days until trip starts (null if no start date)
  int? get daysUntilStart {
    if (startDate == null) return null;
    final now = DateTime.now();
    if (startDate!.isBefore(now)) return 0;
    return startDate!.difference(now).inDays;
  }

  /// Check if trip is ongoing
  bool get isOngoing {
    if (startDate == null || endDate == null) return false;
    final now = DateTime.now();
    return now.isAfter(startDate!) && now.isBefore(endDate!);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Trip && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Trip modules configuration
class TripModules {
  final bool docs;
  final bool gear;
  final bool itinerary;

  const TripModules({
    this.docs = true,
    this.gear = true,
    this.itinerary = false,
  });

  factory TripModules.fromJson(Map<String, dynamic> json) {
    return TripModules(
      docs: json['docs'] as bool? ?? true,
      gear: json['gear'] as bool? ?? true,
      itinerary: json['itinerary'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {'docs': docs, 'gear': gear, 'itinerary': itinerary};
  }

  TripModules copyWith({bool? docs, bool? gear, bool? itinerary}) {
    return TripModules(
      docs: docs ?? this.docs,
      gear: gear ?? this.gear,
      itinerary: itinerary ?? this.itinerary,
    );
  }
}

/// Participant role in a trip
enum ParticipantRole {
  leader('LEADER'),
  member('MEMBER');

  final String value;
  const ParticipantRole(this.value);

  static ParticipantRole fromString(String value) {
    return ParticipantRole.values.firstWhere(
      (role) => role.value == value,
      orElse: () => ParticipantRole.member,
    );
  }
}

/// Participant model
class Participant {
  final String id;
  final String tripId;
  final String? userId;
  final ParticipantRole role;
  final DateTime joinedAt;
  final String? displayName;
  final String? avatarUrl;
  final bool isShadow;

  const Participant({
    required this.id,
    required this.tripId,
    this.userId,
    required this.role,
    required this.joinedAt,
    this.displayName,
    this.avatarUrl,
    this.isShadow = false,
  });

  factory Participant.fromJson(Map<String, dynamic> json) {
    final profiles = json['profiles'] as Map<String, dynamic>?;

    return Participant(
      id: json['id'] as String,
      tripId: json['trip_id'] as String,
      userId: json['user_id'] as String?,
      role: ParticipantRole.fromString(json['role'] as String? ?? 'MEMBER'),
      joinedAt: DateTime.parse(json['joined_at'] as String),
      displayName:
          json['display_name'] as String? ??
          profiles?['display_name'] as String?,
      avatarUrl: profiles?['avatar_url'] as String?,
      isShadow: json['is_shadow'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'trip_id': tripId,
      'user_id': userId,
      'role': role.value,
      'joined_at': joinedAt.toIso8601String(),
      'display_name': displayName,
      'is_shadow': isShadow,
    };
  }

  String get name => displayName ?? 'Unknown';
}
