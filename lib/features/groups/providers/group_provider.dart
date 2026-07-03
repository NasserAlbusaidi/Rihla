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
import '../../../core/utils/safe_deserialize.dart';
import '../../events/models/event_model.dart';
import '../models/group_balance_aggregate_model.dart';
import '../models/group_member_model.dart';
import '../models/group_model.dart';

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

const _callableDeviceVerificationMessage =
    'Could not verify this device. Try again, or update from the Play Store.';

/// Thrown by [GroupService.addShadowMember] (#278) when the placeholder name
/// collides — case-insensitive, trimmed — with an existing real or shadow
/// member. Maps the callable's `already-exists` code. The create flow surfaces
/// the taken [name] per-chip; the group itself is already created, and the
/// remaining names still proceed.
class ShadowMemberNameTakenException implements Exception {
  const ShadowMemberNameTakenException(this.name);

  /// The placeholder name that was rejected (for the UI message).
  final String name;

  @override
  String toString() => 'ShadowMemberNameTakenException(name: $name)';
}

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
  final Future<String> Function({
    required String groupId,
    required String displayName,
  })?
  _addShadowMemberCallableOverride;

  /// Production constructor — uses [FirebaseConfig.firestore] via base class.
  GroupService(this._ref)
    : _currentUserIdOverride = null,
      _joinGroupCallableOverride = null,
      _addShadowMemberCallableOverride = null,
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
    Future<String> Function({
      required String groupId,
      required String displayName,
    })?
    addShadowMemberCallableOverride,
  }) : _currentUserIdOverride = currentUserId,
       _joinGroupCallableOverride = joinGroupCallableOverride,
       _addShadowMemberCallableOverride = addShadowMemberCallableOverride,
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
    String? glyph,
    int? inkIndex,
  }) async {
    final staged = stageGroup(
      name: name,
      currency: currency,
      glyph: glyph,
      inkIndex: inkIndex,
    );
    await staged.ack;
    return staged.group;
  }

  /// Stages a new group: applies the group + invite-code batch to the local
  /// Firestore cache and returns the locally-built [Group] IMMEDIATELY, plus a
  /// single server-ack future (#412/#520). The ack resolves only when the
  /// server confirms — offline it stays pending until reconnect while the SDK
  /// queues the replay, so UI callers race it (`awaitServerAck`) instead of
  /// awaiting it raw (which falsely reports "couldn't create group" after a 15s
  /// timeout even though the group was created locally and will sync).
  ///
  /// The member write is chained AFTER the group batch via `.then` — both
  /// online and on offline replay the group doc is committed before the member
  /// `set()` is evaluated, so the members rule (`isGroupMember` → group exists
  /// with the creator in `memberIds`) holds. This preserves today's sequential
  /// ordering exactly; it does NOT issue the two writes concurrently.
  ///
  /// Throws synchronously if the user is not authenticated.
  ({Group group, Future<void> ack}) stageGroup({
    required String name,
    required String currency,
    String? glyph,
    int? inkIndex,
  }) {
    final uid = _currentUid;
    if (uid == null) {
      throw Exception('User not authenticated');
    }

    final rawName = _ref.read(settingsProvider).deviceName;
    final displayName = rawName.isEmpty ? 'Anonymous' : rawName;

    const uuid = Uuid();
    final groupId = uuid.v4();
    // #524: key the creator's member doc by uid (one member doc per uid),
    // matching joiners (joinGroupByInviteCode → members/{uid}). The members
    // rule now requires the doc id == auth.uid, which bounds client-side member
    // creation to a single deterministic doc and blocks forged duplicates.
    final memberId = uid;
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
      // #287/trip-stamps: a chosen stamp is written ONLY when present. The
      // create rule allow-lists glyph/inkIndex but REJECTS an explicit null
      // (validGroupCreate), so a default group must omit both keys — never a
      // derived fallback. fromDoc reads absence as null.
      'glyph': ?glyph,
      'inkIndex': ?inkIndex,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.set(db.collection('inviteCodes').doc(inviteCode), {
      'groupId': groupId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // #245: seed one default ledger event so a fresh group collapses to
    // create-group → add-expense (no create-event detour). Built via the Event
    // model so the write map comes from the single serializer (toFirestoreMap),
    // mirroring EventService.stageEvent's construction. Shadows added after
    // create are fanned in server-side by addShadowMember; joiners by
    // joinGroupByInviteCode.
    final seededEvent = Event(
      id: uuid.v4(),
      name: name,
      type: EventType.trip,
      groupId: groupId,
      createdBy: uid,
      participantIds: List.unmodifiable([uid]),
      participantNames: Map.unmodifiable({uid: displayName}),
      modules: EventModules.forType(EventType.trip),
      isDeleted: false,
      createdAt: now.toUtc(),
    );

    // Step 2: Add creator as member AFTER the group batch commits. The members
    // subcollection rule requires the group doc to exist with the user in
    // memberIds (isGroupMember check), so the member write is chained on the
    // batch ack — sequential on first-write AND on offline replay. The whole
    // chain is the single ack future the caller races.
    //
    // Step 3 (#245): the seeded event is chained the same way — the events
    // rule reads groups/{gid}.memberIds (isGroupMember), so the group doc must
    // exist first. A failure here rejects the whole ack, identical to the
    // member leg's failure semantics.
    final ack = batch
        .commit()
        .then((_) {
          return db
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
        })
        .then((_) {
          return db
              .collection('groups')
              .doc(groupId)
              .collection('events')
              .doc(seededEvent.id)
              .set(seededEvent.toFirestoreMap());
        });

    // Return a local Group object — serverTimestamp is not readable until
    // the next Firestore snapshot, so use now() as the local createdAt.
    final group = Group(
      id: groupId,
      name: name,
      inviteCode: inviteCode,
      createdBy: uid,
      memberIds: [uid],
      currency: currency,
      createdAt: now,
      updatedAt: now,
      glyph: glyph,
      inkIndex: inkIndex,
    );
    return (group: group, ack: ack);
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
    // #648: NO durable gate on join — "gate creation, not participation."
    // Anonymous users may join and add expenses (the gate stays on create:
    // see stageGroup). The cross-UID swap hole a populated anon shell opens is
    // closed at every swap entry point (#647 + triggerGoogleRestore gate).

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
      'unauthenticated' => _callableDeviceVerificationMessage,
      'invalid-argument' => 'Invalid invite code.',
      'not-found' => 'Invalid invite code.',
      // #279: server rejects a join whose display name collides with an existing
      // member. The screen re-localizes this via the 'already taken in this
      // group' substring (groupJoinNameTaken).
      'already-exists' => 'That name is already taken in this group.',
      'resource-exhausted' => 'Too many attempts. Try again later.',
      // #648: the join path no longer rejects anonymous users, so the callable
      // never returns permission-denied here; any other code falls through to
      // the generic message below.
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

  /// Seed a placeholder ("shadow") member by name (#278).
  ///
  /// Routes through the creator-only `addShadowMember` Cloud callable, which
  /// validates the name, enforces the case-insensitive no-collision rule across
  /// real + shadow members and the 50-member cap, then writes one
  /// `isShadow: true` member doc and returns its `memberId`. The callable is
  /// online-only (no offline replay), so callers gate on connectivity.
  ///
  /// Throws [ShadowMemberNameTakenException] on `already-exists` so the caller
  /// can surface the specific taken name per-chip; any other failure throws a
  /// generic [Exception] with a user-facing message.
  Future<String> addShadowMember({
    required String groupId,
    required String displayName,
  }) async {
    try {
      final override = _addShadowMemberCallableOverride;
      if (override != null) {
        return await override(groupId: groupId, displayName: displayName);
      }

      final result = await FirebaseFunctions.instance
          .httpsCallable('addShadowMember')
          .call({'groupId': groupId, 'displayName': displayName});
      return result.data['memberId'] as String;
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'already-exists') {
        throw ShadowMemberNameTakenException(displayName);
      }
      throw Exception(_addShadowMemberErrorMessage(error.code));
    }
  }

  String _addShadowMemberErrorMessage(String code) {
    return switch (code) {
      'unauthenticated' => _callableDeviceVerificationMessage,
      'permission-denied' => 'Only the group creator can add names.',
      'invalid-argument' => 'That name is not valid.',
      'not-found' => 'That group no longer exists.',
      'failed-precondition' => 'This group cannot take more names right now.',
      _ => 'Could not add that name. Try again.',
    };
  }

  /// Update a group's editable identity in ONE atomic write: display [name]
  /// plus the trip-stamp ([glyph] + [inkIndex]). A null [glyph]/[inkIndex]
  /// CLEARS that field via FieldValue.delete() — the post-write doc has the key
  /// absent (byte-identical to a never-set default), which the deployed
  /// `validCreatorMetadataUpdate` rule admits (strict absent-or-valid guard).
  /// We never write an explicit null. Creator-only is enforced by the rule
  /// (isCreator()), not here.
  Future<void> updateGroupIdentity({
    required String groupId,
    required String name,
    String? glyph,
    int? inkIndex,
  }) async {
    await db.collection('groups').doc(groupId).update({
      'name': name,
      'updatedAt': FieldValue.serverTimestamp(),
      'glyph': glyph ?? FieldValue.delete(),
      'inkIndex': inkIndex ?? FieldValue.delete(),
    });
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
          // #532: decode per-doc so one malformed group can't blank the whole
          // list; the isDeleted filter stays AFTER the (total-parse) decode.
          (snapshot) => decodeDocsSkippingMalformed(
            snapshot.docs,
            Group.fromDoc,
            context: 'watchUserGroups',
          ).where((group) => !group.isDeleted).toList(),
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
          // #532: decode per-doc so one malformed member can't blank the
          // roster. The factory is total-parse except `userId` (the oracle
          // gate), so this only drops a no-userId member — which the server
          // excludes too, keeping allMemberIds in lockstep.
          (snapshot) => decodeDocsSkippingMalformed(
            snapshot.docs,
            (doc) => GroupMember.fromDoc(doc, groupId),
            context: 'watchMembers',
          ),
        );
  }

  /// Reactive stream of the server-maintained balance aggregate (#366).
  ///
  /// One single-doc listener per group (O(G) total from home — NOT the #104
  /// O(G×E) leak). Emits null while the doc is missing (group predates the
  /// first balanceReconciler backfill run), degraded, or malformed — the home
  /// facade falls back to the client once-path compute for those groups.
  Stream<GroupBalanceAggregate?> watchBalanceAggregate(String groupId) {
    return db
        .collection('groups')
        .doc(groupId)
        .collection('aggregates')
        .doc('balance')
        .snapshots()
        .map((doc) => GroupBalanceAggregate.fromDoc(doc.data()));
  }

  /// Reactive stream for one group document.
  Stream<Group?> watchGroup(String groupId) {
    return db.collection('groups').doc(groupId).snapshots().map((doc) {
      if (!doc.exists) return null;
      final group = Group.fromDoc(doc);
      // #518: fence out soft-deleted docs — a single-doc snapshot always
      // EXISTS, so isDeleted must be checked in-memory (no server-side
      // .where filter on a .doc().snapshots() stream).
      return group.isDeleted ? null : group;
    });
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
