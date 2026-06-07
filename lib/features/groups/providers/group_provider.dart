import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/firebase_functions_service.dart';
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
/// base class `db` getter (MIG-05). Uses WriteBatch for createGroup's
/// multi-document writes; joinGroup routes membership mutation through the
/// joinGroupByInviteCode callable.
class GroupService extends FirestoreRepository {
  final Ref _ref;
  final String? _currentUserIdOverride;
  final Future<String> Function({
    required String inviteCode,
    required String displayName,
  })?
  _joinGroupCallableOverride;

  /// Production constructor — uses [FirebaseConfig.firestore] via base class.
  GroupService(this._ref)
    : _currentUserIdOverride = null,
      _joinGroupCallableOverride = null,
      super();

  /// Test constructor — injects a [FakeFirebaseFirestore] for unit testing.
  @visibleForTesting
  GroupService.withFirestore(
    this._ref,
    FirebaseFirestore firestoreDb, {
    String? currentUserId,
    Future<String> Function({
      required String inviteCode,
      required String displayName,
    })?
    joinGroupCallableOverride,
  }) : _currentUserIdOverride = currentUserId,
       _joinGroupCallableOverride = joinGroupCallableOverride,
       super.withFirestore(firestoreDb);

  String? get _currentUid =>
      _currentUserIdOverride ?? FirebaseConfig.currentUser?.uid;

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
  /// NOTE on atomicity: The member subcollection write (Step 2) is intentionally
  /// separate from the group+inviteCode batch (Step 1). Firestore security rules
  /// require the group document to exist with the user in `memberIds` before
  /// allowing writes to the `members` subcollection (via `isGroupMember()`
  /// helper). If Step 2 fails, the group exists without a member doc — this is
  /// recoverable (retry on next app launch) vs. the alternative of relaxing
  /// security rules. Same pattern applies to joinGroup.
  ///
  /// Throws if the user is not authenticated.
  Future<Group> createGroup({
    required String name,
    required String currency,
  }) async {
    final uid = _currentUid;
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
      // #190 HARD REQ #6: new groups carry explicit soft-delete state. Rules
      // require this pair; userGroupsProvider still filters in memory so legacy
      // field-absent groups remain visible.
      'isDeleted': false,
      'deletedAt': null,
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
  /// Group joins are callable-first: the client sends the normalized invite
  /// code and display name to `joinGroupByInviteCode`, and the callable performs
  /// the privileged invite lookup plus `memberIds`/member document writes. The
  /// client never reads `inviteCodes/{code}` and never writes itself into
  /// `groups/{groupId}.memberIds`.
  ///
  /// After the callable returns the group ID, the client reads the group
  /// document to preserve this method's [Future<Group>] contract. A single
  /// short retry covers the edge where Firestore rules have not yet observed
  /// the callable's membership write.
  ///
  /// The invite code is uppercased before the callable invocation (D-13).
  Future<Group> joinGroup({required String inviteCode}) async {
    final uid = _currentUid;
    if (uid == null) {
      throw Exception('User not authenticated');
    }

    final rawName = _ref.read(settingsProvider).deviceName;
    final displayName = rawName.isEmpty ? 'Anonymous' : rawName;
    final normalizedCode = inviteCode.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(normalizedCode)) {
      throw Exception('Invalid invite code');
    }

    final groupId = await _callJoinGroupByInviteCode(
      inviteCode: normalizedCode,
      displayName: displayName,
    );
    final groupDoc = await _readJoinedGroupWithRetry(
      db.collection('groups').doc(groupId),
    );
    return Group.fromDoc(groupDoc);
  }

  Future<String> _callJoinGroupByInviteCode({
    required String inviteCode,
    required String displayName,
  }) async {
    try {
      final override = _joinGroupCallableOverride;
      if (override != null) {
        return await override(inviteCode: inviteCode, displayName: displayName);
      }

      final result = await FirebaseFunctions.instance
          .httpsCallable('joinGroupByInviteCode')
          .call({'inviteCode': inviteCode, 'displayName': displayName});
      return result.data['groupId'] as String;
    } on FirebaseFunctionsException catch (error) {
      throw Exception(_joinGroupErrorMessage(error.code));
    }
  }

  String _joinGroupErrorMessage(String code) {
    return switch (code) {
      'unauthenticated' => 'Please sign in and try again.',
      'invalid-argument' => 'Invalid invite code.',
      'not-found' => 'Invalid invite code.',
      'resource-exhausted' => 'Too many attempts. Try again later.',
      _ => 'Could not join group. Try again.',
    };
  }

  Future<DocumentSnapshot> _readJoinedGroupWithRetry(
    DocumentReference groupRef,
  ) async {
    Future<DocumentSnapshot?> tryRead() async {
      try {
        final snapshot = await groupRef.get();
        return snapshot.exists ? snapshot : null;
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied') {
          return null;
        }
        rethrow;
      }
    }

    var snapshot = await tryRead();
    if (snapshot == null) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      snapshot = await tryRead();
    }
    if (snapshot == null) {
      throw Exception('Could not join group. Try again.');
    }
    return snapshot;
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

  /// Remove the current user from the group (server-authoritative, #290).
  ///
  /// Routes through the `leaveGroup` Cloud callable, which recomputes the
  /// caller's net balance, refuses with `failed-precondition` on any non-zero
  /// net, then removes the UID from `memberIds` + deletes their member doc +
  /// logs `member_left`. The client performs NO direct Firestore writes — the
  /// direct self-leave path is locked at the rules layer (`validSelfLeave`
  /// dropped from group `allow update`). This closes the offline orphan-debt
  /// hole where the old UI-side gate was skipped when balances were null.
  ///
  /// Throws [FirebaseFunctionsException]; the danger section maps the code.
  Future<void> leaveGroup({required String groupId}) async {
    await _ref
        .read(firebaseFunctionsServiceProvider)
        .leaveGroup(groupId: groupId);
  }

  /// Remove a specific member from the group (server-authoritative, #318).
  ///
  /// Routes through the creator-only `removeMember` Cloud callable, which
  /// recomputes the TARGET member's net balance, refuses with
  /// `failed-precondition` on any non-zero net, then removes the UID from
  /// `memberIds` + deletes their member doc + logs `member_left`. The client
  /// performs NO direct Firestore writes — the direct creator-remove path is
  /// locked at the rules layer (`validCreatorRemoveMember` dropped from group
  /// `allow update`). This closes the offline orphan-debt hole where the old
  /// UI-side gate was skipped when balances were null.
  ///
  /// Throws [FirebaseFunctionsException]; the members section maps the code.
  Future<void> removeMember({
    required String groupId,
    required String userId,
  }) async {
    await _ref
        .read(firebaseFunctionsServiceProvider)
        .removeMember(groupId: groupId, targetUserId: userId);
  }

  /// Delete a group (server-authoritative, #190).
  ///
  /// Routes through the `deleteGroup` Cloud callable, which recomputes per-actor
  /// net balances exactly as [BalanceCalculator], refuses with
  /// `failed-precondition` on any non-zero net, then SOFT-deletes the group +
  /// its events (keeping the append-only expense/settlement records reachable).
  /// The client performs NO direct Firestore writes — the direct delete path is
  /// locked at the rules layer (`allow delete: if false;`).
  ///
  /// Throws [FirebaseFunctionsException]; callers (the danger section) map the
  /// code to a user-facing message.
  Future<void> deleteGroup({required String groupId}) async {
    await _ref
        .read(firebaseFunctionsServiceProvider)
        .deleteGroup(groupId: groupId);
  }

  /// Reactive stream of all non-deleted groups for one user.
  ///
  /// Uses the existing `memberIds arrayContains` + `createdAt DESC` query, then
  /// filters `isDeleted` in memory so legacy groups without the field remain
  /// visible (#190).
  Stream<List<Group>> watchUserGroups(String uid) {
    return db
        .collection('groups')
        .where('memberIds', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(Group.fromDoc)
              .where((group) => !group.isDeleted)
              .toList(),
        );
  }

  /// Reactive stream of all members in a specific group.
  Stream<List<GroupMember>> watchMembers(String groupId) {
    return db
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
  }

  /// Reactive stream for one group document.
  Stream<Group?> watchGroup(String groupId) {
    return db
        .collection('groups')
        .doc(groupId)
        .snapshots()
        .map((doc) => doc.exists ? Group.fromDoc(doc) : null);
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

  return ref.watch(groupServiceProvider).watchUserGroups(uid);
});

/// Reactive stream of all members in a specific group.
///
/// Ordered by join time (ascending) so the CREATOR appears first.
final groupMembersProvider = StreamProvider.family<List<GroupMember>, String>((
  ref,
  groupId,
) {
  return ref.watch(groupServiceProvider).watchMembers(groupId);
});

/// Reactive stream for a single group by ID.
///
/// Returns null if the group does not exist.
final groupDetailProvider = StreamProvider.family<Group?, String>((
  ref,
  groupId,
) {
  return ref.watch(groupServiceProvider).watchGroup(groupId);
});
