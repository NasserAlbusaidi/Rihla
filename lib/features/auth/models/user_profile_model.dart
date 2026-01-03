class UserProfile {
  final String id;
  final String? displayName;
  final String? avatarUrl; // This will store the SVG avatar ID/key
  final DateTime? updatedAt;

  UserProfile({
    required this.id,
    this.displayName,
    this.avatarUrl,
    this.updatedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  UserProfile copyWith({
    String? id,
    String? displayName,
    String? avatarUrl,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
