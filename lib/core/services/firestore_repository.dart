import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../config/firebase_config.dart';

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
  @visibleForTesting
  FirestoreRepository.withFirestore(FirebaseFirestore db) : _db = db;

  /// Access the underlying Firestore instance (db).
  FirebaseFirestore get db => _db;

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
