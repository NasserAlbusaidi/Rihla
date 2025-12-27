/// Shadow Profile model for placeholder participants
class ShadowProfile {
  final String id;
  final String tripId;
  final String? userId; // null for shadows, set after merge
  final String? displayName; // used for shadows
  final bool isShadow;
  final String? createdBy;
  final DateTime createdAt;
  final String? role;
  final String? avatarUrl;

  const ShadowProfile({
    required this.id,
    required this.tripId,
    this.userId,
    this.displayName,
    this.isShadow = true,
    this.createdBy,
    required this.createdAt,
    this.role,
    this.avatarUrl,
  });

  /// Name to display (displayName for shadows, fetch from profiles for real)
  String get name => displayName ?? 'Unknown';

  /// Check if this is a real user (merged or joined directly)
  bool get isRealUser => !isShadow && userId != null;

  /// Check if can be merged (is shadow and not yet merged)
  bool get canMerge => isShadow && userId == null;

  factory ShadowProfile.fromJson(Map<String, dynamic> json) {
    return ShadowProfile(
      id: json['id'] as String,
      tripId: json['trip_id'] as String,
      userId: json['user_id'] as String?,
      displayName: json['display_name'] as String?,
      isShadow: json['is_shadow'] as bool? ?? false,
      createdBy: json['created_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      role: json['role'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'trip_id': tripId,
      'user_id': userId,
      'display_name': displayName,
      'is_shadow': isShadow,
      'created_by': createdBy,
      'role': role,
      'avatar_url': avatarUrl,
    };
  }

  ShadowProfile copyWith({
    String? id,
    String? tripId,
    String? userId,
    String? displayName,
    bool? isShadow,
    String? createdBy,
    DateTime? createdAt,
    String? role,
    String? avatarUrl,
  }) {
    return ShadowProfile(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      isShadow: isShadow ?? this.isShadow,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      role: role ?? this.role,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}
