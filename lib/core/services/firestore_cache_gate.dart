import 'package:cloud_firestore/cloud_firestore.dart';

/// Seam over the Firestore SDK's on-device persistence cache.
///
/// The cross-UID leak (#45) is sealed by clearing this cache on a UID swap.
/// `FakeFirebaseFirestore.clearPersistence` is an in-memory no-op that models
/// neither `terminate()` nor the "instance must not be started" precondition,
/// so [CacheUidBarrier] is verified against this abstraction in unit tests and
/// the real eviction is validated on-device (RD-QA).
abstract class FirestoreCacheGate {
  /// Clears the on-device persistence cache. Per the cloud_firestore contract
  /// this is only legal while the instance is not started — i.e. at the
  /// cold-start boot barrier, before any read/write (only the `settings`
  /// assignment in `FirebaseConfig.initialize` may precede it).
  Future<void> clearPersistence();
}

class FirebaseFirestoreCacheGate implements FirestoreCacheGate {
  FirebaseFirestoreCacheGate([FirebaseFirestore? firestore])
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<void> clearPersistence() => _firestore.clearPersistence();
}
