import 'package:flutter/foundation.dart';

import '../config/firebase_config.dart';
import 'firestore_repository.dart';

typedef StagedDisplayNamePropagation = ({Future<void> ack});

class DisplayNamePropagationService extends FirestoreRepository {
  DisplayNamePropagationService();

  @visibleForTesting
  DisplayNamePropagationService.withFirestore(super.db) : super.withFirestore();

  Future<StagedDisplayNamePropagation?> stage(String displayName) async {
    final uid = FirebaseConfig.currentUser?.uid;
    if (uid == null) return null;

    final groupsSnap = await db
        .collection('groups')
        .where('memberIds', arrayContains: uid)
        .get();

    final batch = db.batch();
    for (final groupDoc in groupsSnap.docs) {
      final membersSnap = await db
          .collection('groups')
          .doc(groupDoc.id)
          .collection('members')
          .where('userId', isEqualTo: uid)
          .get();

      for (final memberDoc in membersSnap.docs) {
        batch.update(memberDoc.reference, {'displayName': displayName});
      }
    }

    return (ack: batch.commit());
  }
}
