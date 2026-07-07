import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../config/firebase_config.dart';
import '../utils/listen_recovery.dart';

/// Abstract base class for all Firestore repository services.
///
/// Provides a production constructor that uses the [FirebaseConfig] singleton
/// and a test constructor ([FirestoreRepository.withFirestore]) that accepts a
/// [FakeFirebaseFirestore] for unit testing (mirrors EventService pattern).
///
/// Concrete service classes extend this and call [eventSubcollection] to get
/// a typed reference to any event module subcollection.
abstract class FirestoreRepository {
  final FirebaseFirestore _db;

  /// Production constructor -- uses [FirebaseConfig.firestore] singleton.
  FirestoreRepository() : _db = FirebaseConfig.firestore;

  /// Test constructor -- injects a [FakeFirebaseFirestore] for unit testing.
  ///
  /// Marked [protected] so subclasses can call `super.withFirestore(db)` in
  /// their own `@visibleForTesting` named constructors.
  @protected
  FirestoreRepository.withFirestore(FirebaseFirestore db) : _db = db;

  /// Access the underlying Firestore instance (db).
  FirebaseFirestore get db => _db;

  /// Wraps a Firestore listen with the #997 bounded permission-denied
  /// recovery (see [recoverDeniedListen]). Every group-scoped `watch*` in the
  /// app goes through this; `watchUserGroups` deliberately does not (a
  /// collection query returns an empty match set instead of a rule error, so
  /// it self-heals on the next snapshot).
  @protected
  Stream<T> recoverListen<T>(Stream<T> Function() subscribe) {
    return recoverDeniedListen(
      subscribe,
      pendingWritesBarrier: _db.waitForPendingWrites,
    );
  }

  /// Returns a typed reference to a module subcollection nested under an event.
  ///
  /// Path: `groups/{groupId}/events/{eventId}/{module}`
  ///
  /// Example:
  /// ```dart
  /// final ref = eventSubcollection('g1', 'e1', 'expenses');
  /// // ref.path == 'groups/g1/events/e1/expenses'
  /// ```
  CollectionReference<Map<String, dynamic>> eventSubcollection(
    String groupId,
    String eventId,
    String module,
  ) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('events')
        .doc(eventId)
        .collection(module);
  }
}
