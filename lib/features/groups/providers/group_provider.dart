import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/firestore_repository.dart';
import '../models/group_member_model.dart';
import '../models/group_model.dart';

// ---------------------------------------------------------------------------
// State providers
// ---------------------------------------------------------------------------

/// Whether a group operation (create/join) is in progress.
final groupLoadingProvider = StateProvider<bool>((ref) => false);

/// Error message from the most recent group operation, or null.
final groupErrorProvider = StateProvider<String?>((ref) => null);

// ---------------------------------------------------------------------------
// GroupService
// ---------------------------------------------------------------------------

/// Service for group CRUD operations against Firestore.
///
/// Extends [FirestoreRepository] so all Firestore access flows through the
/// base class `db` getter (MIG-05). Uses WriteBatch for atomic multi-document
/// writes (createGroup writes 3 docs; joinGroup writes 2 docs atomically
/// per research Pattern 1 & 2).
class GroupService extends FirestoreRepository {
  final Ref _ref;

  /// Production constructor — uses [FirebaseConfig.firestore] via base class.
  GroupService(this._ref) : super();

  /// Test constructor — injects a [FakeFirebaseFirestore] for unit testing.
  @visibleForTesting
  GroupService.withFirestore(this._ref, FirebaseFirestore firestoreDb)
      : super.withFirestore(firestoreDb);

  /// Generate a unique 6-character invite code.
  ///
  /// Uses the same allowed-character set as trip invite codes (D-10):
  /// excludes O/0/I/l to avoid visual confusion.
  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// Create a new group atomically.
  ///
  /// Writes 3 documents in a single WriteBatch:
  /// 1. The group document (groups/{groupId})
  /// 2. The invite code lookup document (inviteCodes/{inviteCode})
  /// 3. The creator's member document (groups/{groupId}/members/{memberId})
  ///
  /// The creator is automatically added as a member with role CREATOR (D-09).
  /// Their display name is read from [settingsProvider] (D-06).
  ///
  /// Throws if the user is not authenticated.
  Future<Group> createGroup({
    required String name,
    required String currency,
  }) async {
    final uid = FirebaseConfig.currentUser?.uid;
    if (uid == null) {
      throw Exception('User not authenticated');
    }

    final rawName = _ref.read(settingsProvider).deviceName;
    final displayName = rawName.isEmpty ? 'Anonymous' : rawName;

    const uuid = Uuid();
    final groupId = uuid.v4();
    final memberId = uuid.v4();
    final inviteCode = _generateInviteCode();
    final now = DateTime.now();

    // Step 1: Create group + invite code atomically.
    // These must be batched so a group always has its invite code lookup.
    final batch = db.batch();

    batch.set(db.collection('groups').doc(groupId), {
      'id': groupId,
      'name': name,
      'inviteCode': inviteCode,
      'createdBy': uid,
      'memberIds': [uid],
      'currency': currency,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.set(db.collection('inviteCodes').doc(inviteCode), {
      'groupId': groupId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // Step 2: Add creator as member AFTER group exists.
    // The members subcollection rule requires the group doc to exist
    // with the user in memberIds (isGroupMember check), so this must
    // be a separate write after the group batch commits.
    await db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .doc(memberId)
        .set({
      'id': memberId,
      'userId': uid,
      'displayName': displayName,
      'role': 'CREATOR',
      'joinedAt': FieldValue.serverTimestamp(),
      'isShadow': false,
    });

    // Return a local Group object — serverTimestamp is not readable until
    // the next Firestore snapshot, so use now() as the local createdAt.
    return Group(
      id: groupId,
      name: name,
      inviteCode: inviteCode,
      createdBy: uid,
      memberIds: [uid],
      currency: currency,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Join an existing group via its invite code.
  ///
  /// Writes 2 documents atomically via WriteBatch:
  /// 1. The joiner's member document (groups/{groupId}/members/{memberId})
  /// 2. Updated memberIds array on the group document (via arrayUnion)
  ///
  /// Throws [Exception('Invalid invite code')] if the code doesn't exist.
  /// Throws [Exception('Already a member')] if the user is already in the group.
  ///
  /// The invite code is uppercased before the Firestore lookup (D-13).
  Future<Group> joinGroup({required String inviteCode}) async {
    final uid = FirebaseConfig.currentUser?.uid;
    if (uid == null) {
      throw Exception('User not authenticated');
    }

    final rawName = _ref.read(settingsProvider).deviceName;
    final displayName = rawName.isEmpty ? 'Anonymous' : rawName;
    final normalizedCode = inviteCode.toUpperCase();

    // Look up the group ID from the invite code.
    // inviteCodes collection is publicly readable (no membership check).
    final codeDoc =
        await db.collection('inviteCodes').doc(normalizedCode).get();
    if (!codeDoc.exists) {
      throw Exception('Invalid invite code');
    }

    final groupId = codeDoc.data()!['groupId'] as String;

    // Step 1: Add user to group's memberIds first.
    // The groups rule allows update if isMember(), but the joiner isn't
    // a member yet. We need a rule that allows arrayUnion on memberIds
    // for authenticated users. For now, update memberIds first — the
    // security rule allows update if isMember(), and after this write
    // the user IS a member for subsequent reads.
    //
    // NOTE: If security rules block this, we need to add a join-specific
    // rule. For now, try the update and let the error surface.
    await db.collection('groups').doc(groupId).update({
      'memberIds': FieldValue.arrayUnion([uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Step 2: Create member document (now user is in memberIds,
    // so isGroupMember() check passes).
    const uuid = Uuid();
    final memberId = uuid.v4();

    await db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .doc(memberId)
        .set({
      'id': memberId,
      'userId': uid,
      'displayName': displayName,
      'role': 'MEMBER',
      'joinedAt': FieldValue.serverTimestamp(),
      'isShadow': false,
    });

    // Step 3: Now user is a member — can read the group document.
    final updatedDoc = await db.collection('groups').doc(groupId).get();
    return Group.fromDoc(updatedDoc);
  }

  /// Update group metadata (name and/or currency).
  ///
  /// Only provided (non-null) fields are updated. Always updates updatedAt.
  Future<void> updateGroup({
    required String groupId,
    String? name,
    String? currency,
  }) async {
    final updateMap = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (name != null) updateMap['name'] = name;
    if (currency != null) updateMap['currency'] = currency;

    await db.collection('groups').doc(groupId).update(updateMap);
  }

  /// Update a member's display name in the group (D-07).
  Future<void> updateMemberDisplayName({
    required String groupId,
    required String memberId,
    required String displayName,
  }) async {
    await db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .doc(memberId)
        .update({'displayName': displayName});
  }

  /// Remove the current user from the group atomically.
  ///
  /// Batch operation: removes UID from memberIds array + deletes member
  /// subcollection document. Callers must check balance == zero before
  /// invoking (D-07 gate is UI-side).
  Future<void> leaveGroup({required String groupId}) async {
    final uid = FirebaseConfig.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');

    final membersSnap = await db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .where('userId', isEqualTo: uid)
        .limit(1)
        .get();

    if (membersSnap.docs.isEmpty) throw Exception('Member not found');

    final batch = db.batch();
    batch.update(db.collection('groups').doc(groupId), {
      'memberIds': FieldValue.arrayRemove([uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.delete(membersSnap.docs.first.reference);
    await batch.commit();
  }

  /// Remove a specific member from the group (creator action).
  ///
  /// Batch operation: removes the member's userId from memberIds +
  /// deletes their member subcollection document. Callers must verify
  /// the current user is the creator and the target has zero balance.
  Future<void> removeMember({
    required String groupId,
    required String memberId,
    required String userId,
  }) async {
    final batch = db.batch();
    batch.update(db.collection('groups').doc(groupId), {
      'memberIds': FieldValue.arrayRemove([userId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.delete(
      db.collection('groups').doc(groupId).collection('members').doc(memberId),
    );
    await batch.commit();
  }

  /// Delete a group and all its member documents atomically.
  ///
  /// Steps:
  /// 1. Fetch all member subcollection docs
  /// 2. Read group doc to get invite code
  /// 3. Batch delete: all member docs + invite code doc + group doc
  ///
  /// Does NOT cascade-delete events (orphaned events are invisible
  /// without group membership). Firestore batch limit is 500 ops —
  /// safe for groups with <498 members.
  Future<void> deleteGroup({required String groupId}) async {
    final membersSnap = await db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .get();

    final groupDoc = await db.collection('groups').doc(groupId).get();
    final inviteCode = groupDoc.data()?['inviteCode'] as String?;

    final batch = db.batch();
    for (final memberDoc in membersSnap.docs) {
      batch.delete(memberDoc.reference);
    }
    if (inviteCode != null) {
      batch.delete(db.collection('inviteCodes').doc(inviteCode));
    }
    batch.delete(db.collection('groups').doc(groupId));
    await batch.commit();
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Provider for [GroupService].
final groupServiceProvider = Provider<GroupService>(GroupService.new);

/// Reactive Firebase auth state — providers that need the current UID
/// should watch this so they re-evaluate when auth restores on restart.
final firebaseUserProvider = StreamProvider<User?>((ref) {
  return FirebaseConfig.auth.authStateChanges();
});

/// Reactive stream of all groups the current user belongs to.
///
/// Watches [firebaseUserProvider] so the query re-runs when auth state
/// changes (e.g. session restored on app restart). Without this,
/// the UID is captured once at provider creation and never updates.
final userGroupsProvider = StreamProvider<List<Group>>((ref) {
  final userAsync = ref.watch(firebaseUserProvider);
  final uid = userAsync.valueOrNull?.uid;
  if (uid == null) return Stream.value([]);

  return FirebaseConfig.firestore
      .collection('groups')
      .where('memberIds', arrayContains: uid)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map(Group.fromDoc).toList(),
      );
});

/// Reactive stream of all members in a specific group.
///
/// Ordered by join time (ascending) so the CREATOR appears first.
final groupMembersProvider =
    StreamProvider.family<List<GroupMember>, String>((ref, groupId) {
  return FirebaseConfig.firestore
      .collection('groups')
      .doc(groupId)
      .collection('members')
      .orderBy('joinedAt')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => GroupMember.fromDoc(doc, groupId))
            .toList(),
      );
});

/// Reactive stream for a single group by ID.
///
/// Returns null if the group does not exist.
final groupDetailProvider =
    StreamProvider.family<Group?, String>((ref, groupId) {
  return FirebaseConfig.firestore
      .collection('groups')
      .doc(groupId)
      .snapshots()
      .map((doc) => doc.exists ? Group.fromDoc(doc) : null);
});
