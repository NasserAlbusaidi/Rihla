import 'package:cloud_firestore/cloud_firestore.dart';

/// Immutable model representing a member of a group.
///
/// Roles are strings ('CREATOR' or 'MEMBER') — not enum — for
/// forward-compatible serialization.
class GroupMember {
  final String id;
  final String groupId;
  final String userId;
  final String displayName;

  /// Role string: 'CREATOR' for the group creator, 'MEMBER' for everyone else.
  final String role;
  final bool isShadow;
  final bool isTombstone;
  final DateTime joinedAt;

  const GroupMember({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.displayName,
    required this.role,
    this.isShadow = false,
    this.isTombstone = false,
    required this.joinedAt,
  });

  /// Create GroupMember from a Firestore members subcollection document.
  factory GroupMember.fromDoc(DocumentSnapshot doc, String groupId) {
    final data = doc.data() as Map<String, dynamic>;
    return GroupMember(
      id: doc.id,
      groupId: groupId,
      userId: data['userId'] as String,
      displayName: data['displayName'] as String,
      role: data['role'] as String,
      isShadow: data['isShadow'] as bool? ?? false,
      isTombstone: data['isTombstone'] as bool? ?? false,
      joinedAt: (data['joinedAt'] as Timestamp).toDate(),
    );
  }

  /// Create GroupMember from a SQLite row map.
  factory GroupMember.fromMap(Map<String, dynamic> map) {
    return GroupMember(
      id: map['id'] as String,
      groupId: map['group_id'] as String,
      userId: map['user_id'] as String,
      displayName: map['display_name'] as String,
      role: map['role'] as String? ?? 'MEMBER',
      isShadow: (map['is_shadow'] as int?) == 1,
      isTombstone: (map['is_tombstone'] as int?) == 1,
      joinedAt: DateTime.parse(map['joined_at'] as String),
    );
  }

  /// Convert GroupMember to a SQLite row map for insert/replace.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'group_id': groupId,
      'user_id': userId,
      'display_name': displayName,
      'role': role,
      'is_shadow': isShadow ? 1 : 0,
      'is_tombstone': isTombstone ? 1 : 0,
      'joined_at': joinedAt.toIso8601String(),
      'synced_at': DateTime.now().toIso8601String(),
    };
  }

  /// Create a copy with updated fields (immutable pattern).
  GroupMember copyWith({
    String? id,
    String? groupId,
    String? userId,
    String? displayName,
    String? role,
    bool? isShadow,
    bool? isTombstone,
    DateTime? joinedAt,
  }) {
    return GroupMember(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      isShadow: isShadow ?? this.isShadow,
      isTombstone: isTombstone ?? this.isTombstone,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }

  /// Whether this member has the CREATOR role.
  bool get isCreator => role == 'CREATOR';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupMember &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'GroupMember(id: $id, displayName: $displayName, role: $role)';
}
