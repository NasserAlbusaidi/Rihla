/// Participant role in a trip.
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
