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
    await eventSubcollection(groupId, eventId, 'sub_groups').doc(id).set(data);
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
  }

  /// Remove a member from a sub-group's members subcollection.
  Future<void> removeMember({
    required String groupId,
    required String eventId,
    required String subGroupId,
    required String memberId,
  }) async {
    await eventSubcollection(groupId, eventId, 'sub_groups')
        .doc(subGroupId)
        .collection('members')
        .doc(memberId)
        .delete();
  }

  /// Hard-delete a sub-group document.
  Future<void> deleteSubGroup({
    required String groupId,
    required String eventId,
    required String subGroupId,
  }) async {
    await eventSubcollection(groupId, eventId, 'sub_groups')
        .doc(subGroupId)
        .delete();
  }
}
