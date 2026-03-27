import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/firestore_repository.dart';
import '../models/sub_group_model.dart';

/// Firestore-backed service for sub-group CRUD operations.
///
/// Extends [FirestoreRepository] to write sub-groups to the
/// `groups/{groupId}/events/{eventId}/sub_groups` subcollection.
/// Members are stored in a nested `members` subcollection.
class SubGroupService extends FirestoreRepository {
  SubGroupService() : super();

  @visibleForTesting
  SubGroupService.withFirestore(FirebaseFirestore db) : super.withFirestore(db);

  /// Stream of sub-groups for an event, ordered by createdAt.
  Stream<List<SubGroup>> watchSubGroups(String groupId, String eventId) {
    return eventSubcollection(groupId, eventId, 'sub_groups')
        .orderBy('createdAt')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (doc) =>
                    SubGroup.fromFirestore({...doc.data(), 'id': doc.id}),
              )
              .toList(),
        );
  }

  /// Create a new sub-group in the event subcollection.
  Future<SubGroup> createSubGroup({
    required String groupId,
    required String eventId,
    required String name,
    required String type,
    int capacity = 4,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();
    final data = <String, dynamic>{
      'id': id,
      'eventId': eventId,
      'name': name,
      'type': type,
      'capacity': capacity,
      'createdAt': now.toIso8601String(),
    };
    try {
      await eventSubcollection(groupId, eventId, 'sub_groups').doc(id).set(data);
    } on FirebaseException catch (e) {
      debugPrint('SubGroupService.createSubGroup failed: ${e.code} ${e.message}');
      rethrow;
    }
    return SubGroup.fromFirestore(data);
  }

  /// Add a member to a sub-group's members subcollection.
  Future<void> addMember({
    required String groupId,
    required String eventId,
    required String subGroupId,
    required String participantId,
    required String displayName,
  }) async {
    final memberId = const Uuid().v4();
    try {
      await eventSubcollection(groupId, eventId, 'sub_groups')
          .doc(subGroupId)
          .collection('members')
          .doc(memberId)
          .set({
        'id': memberId,
        'participantId': participantId,
        'displayName': displayName,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
    } on FirebaseException catch (e) {
      debugPrint('SubGroupService.addMember failed: ${e.code} ${e.message}');
      rethrow;
    }
  }

  /// Remove a member from a sub-group's members subcollection.
  Future<void> removeMember({
    required String groupId,
    required String eventId,
    required String subGroupId,
    required String memberId,
  }) async {
    try {
      await eventSubcollection(groupId, eventId, 'sub_groups')
          .doc(subGroupId)
          .collection('members')
          .doc(memberId)
          .delete();
    } on FirebaseException catch (e) {
      debugPrint('SubGroupService.removeMember failed: ${e.code} ${e.message}');
      rethrow;
    }
  }

  /// Hard-delete a sub-group document.
  Future<void> deleteSubGroup({
    required String groupId,
    required String eventId,
    required String subGroupId,
  }) async {
    try {
      await eventSubcollection(groupId, eventId, 'sub_groups')
          .doc(subGroupId)
          .delete();
    } on FirebaseException catch (e) {
      debugPrint('SubGroupService.deleteSubGroup failed: ${e.code} ${e.message}');
      rethrow;
    }
  }

  /// Update a sub-group's name and/or capacity.
  Future<void> updateSubGroup({
    required String groupId,
    required String eventId,
    required String subGroupId,
    String? name,
    int? capacity,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (capacity != null) updates['capacity'] = capacity;
    if (updates.isEmpty) return;
    try {
      await eventSubcollection(groupId, eventId, 'sub_groups')
          .doc(subGroupId)
          .update(updates);
    } on FirebaseException catch (e) {
      debugPrint('SubGroupService.updateSubGroup failed: ${e.code} ${e.message}');
      rethrow;
    }
  }
}
