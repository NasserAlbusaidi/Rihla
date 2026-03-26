import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/firestore_repository.dart';
import '../models/gear_item_model.dart';

/// Firestore-backed service for gear item CRUD operations.
///
/// Extends [FirestoreRepository] to write gear items to the
/// `groups/{groupId}/events/{eventId}/gear_items` subcollection.
class GearService extends FirestoreRepository {
  GearService() : super();

  @visibleForTesting
  GearService.withFirestore(FirebaseFirestore db) : super.withFirestore(db);

  /// Stream of non-deleted gear items for an event, ordered by sequenceId.
  Stream<List<GearItem>> watchGearItems(String groupId, String eventId) {
    return eventSubcollection(groupId, eventId, 'gear_items')
        .where('isDeleted', isEqualTo: false)
        .orderBy('sequenceId')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (doc) =>
                    GearItem.fromFirestore({...doc.data(), 'id': doc.id}),
              )
              .toList(),
        );
  }

  /// Add a new gear item to the event subcollection.
  Future<GearItem> addGearItem({
    required String groupId,
    required String eventId,
    required String itemName,
    String? assignedTo,
    bool isHighPriority = false,
    int sequenceId = 0,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();
    final data = <String, dynamic>{
      'id': id,
      'eventId': eventId,
      'itemName': itemName,
      'assignedTo': assignedTo,
      'isPacked': false,
      'sequenceId': sequenceId,
      'isHighPriority': isHighPriority,
      'isDeleted': false,
      'deletedAt': null,
      'createdAt': now.toIso8601String(),
    };
    await eventSubcollection(groupId, eventId, 'gear_items').doc(id).set(data);
    return GearItem.fromFirestore(data);
  }

  /// Toggle the packed state of a gear item.
  Future<void> togglePacked({
    required String groupId,
    required String eventId,
    required String gearItemId,
    required bool isPacked,
  }) async {
    await eventSubcollection(groupId, eventId, 'gear_items')
        .doc(gearItemId)
        .update({'isPacked': isPacked});
  }

  /// Update editable fields on a gear item.
  Future<void> updateGearItem({
    required String groupId,
    required String eventId,
    required String gearItemId,
    String? itemName,
    String? assignedTo,
    bool? isHighPriority,
  }) async {
    final updates = <String, dynamic>{};
    if (itemName != null) updates['itemName'] = itemName;
    if (assignedTo != null) updates['assignedTo'] = assignedTo;
    if (isHighPriority != null) updates['isHighPriority'] = isHighPriority;
    if (updates.isNotEmpty) {
      await eventSubcollection(groupId, eventId, 'gear_items')
          .doc(gearItemId)
          .update(updates);
    }
  }

  /// Soft-delete a gear item by setting isDeleted=true.
  Future<void> deleteGearItem({
    required String groupId,
    required String eventId,
    required String gearItemId,
  }) async {
    await eventSubcollection(groupId, eventId, 'gear_items')
        .doc(gearItemId)
        .update({
      'isDeleted': true,
      'deletedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
