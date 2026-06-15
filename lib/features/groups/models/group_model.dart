import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_parse.dart';

/// Immutable model representing a persistent group in Rihla.
///
/// Groups are the top-level construct that persist across events.
/// Members accumulate financial history at the group level.
class Group {
  final String id;
  final String name;
  final String inviteCode;
  final String createdBy;
  final List<String> memberIds;
  final String currency;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Soft-delete flag. Group deletion is server-authoritative (#190): the
  /// `deleteGroup` callable flips this to `true` (it never hard-deletes the
  /// doc). `userGroupsProvider` filters `!group.isDeleted` in memory so
  /// soft-deleted groups drop off Home while legacy field-absent groups and
  /// append-only money records stay reachable.
  final bool isDeleted;
  final DateTime? deletedAt;

  const Group({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.createdBy,
    required this.memberIds,
    this.currency = 'OMR',
    required this.createdAt,
    this.updatedAt,
    this.isDeleted = false,
    this.deletedAt,
  });

  /// Create Group from a Firestore document snapshot.
  ///
  /// memberIds is stored as an array field (not a map) per D-14.
  ///
  /// TOTAL-PARSE (#532): every field is salvaged from a present-but-wrong-type
  /// value instead of hard-cast, so one malformed group doc can never throw a
  /// `CastError` that blanks the whole `watchUserGroups` list. (Groups are not
  /// a balance-oracle input, so this layer is display-robustness; the per-doc
  /// skip-net in `group_provider.dart` is the final catch for a null `data()`.)
  factory Group.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Group(
      id: doc.id,
      name: data['name'] is String ? data['name'] as String : '',
      inviteCode:
          data['inviteCode'] is String ? data['inviteCode'] as String : '',
      createdBy: data['createdBy'] is String ? data['createdBy'] as String : '',
      memberIds: data['memberIds'] is List
          ? (data['memberIds'] as List).whereType<String>().toList()
          : const <String>[],
      currency: data['currency'] is String ? data['currency'] as String : 'OMR',
      createdAt: dateOrNow(data['createdAt']),
      updatedAt: dateOrNull(data['updatedAt']),
      isDeleted: data['isDeleted'] == true,
      deletedAt: dateOrNull(data['deletedAt']),
    );
  }

  /// Create Group from a SQLite row map.
  factory Group.fromMap(Map<String, dynamic> map) {
    return Group(
      id: map['id'] as String,
      name: map['name'] as String,
      inviteCode: map['invite_code'] as String,
      createdBy: map['created_by'] as String,
      memberIds: (jsonDecode(map['member_ids'] as String) as List)
          .cast<String>(),
      currency: map['currency'] as String? ?? 'OMR',
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
      isDeleted: (map['is_deleted'] as int?) == 1,
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String)
          : null,
    );
  }

  /// Convert Group to a SQLite row map for insert/replace.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'invite_code': inviteCode,
      'created_by': createdBy,
      'member_ids': jsonEncode(memberIds),
      'currency': currency,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'is_deleted': isDeleted ? 1 : 0,
      'deleted_at': deletedAt?.toIso8601String(),
      'synced_at': DateTime.now().toIso8601String(),
    };
  }

  /// Create a copy with updated fields (immutable pattern).
  Group copyWith({
    String? id,
    String? name,
    String? inviteCode,
    String? createdBy,
    List<String>? memberIds,
    String? currency,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
    DateTime? deletedAt,
  }) {
    return Group(
      id: id ?? this.id,
      name: name ?? this.name,
      inviteCode: inviteCode ?? this.inviteCode,
      createdBy: createdBy ?? this.createdBy,
      memberIds: memberIds ?? this.memberIds,
      currency: currency ?? this.currency,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Group && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Group(id: $id, name: $name, members: ${memberIds.length})';
}
