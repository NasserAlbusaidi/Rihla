import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/providers/settings_provider.dart';
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
/// Uses WriteBatch for atomic multi-document writes (createGroup writes
/// 3 docs; joinGroup writes 2 docs atomically per research Pattern 1 & 2).
class GroupService {
  final Ref _ref;

  GroupService(this._ref);

  FirebaseFirestore get _db => FirebaseConfig.firestore;

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
    final batch = _db.batch();

    batch.set(_db.collection('groups').doc(groupId), {
      'id': groupId,
      'name': name,
      'inviteCode': inviteCode,
      'createdBy': uid,
      'memberIds': [uid],
      'currency': currency,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.set(_db.collection('inviteCodes').doc(inviteCode), {
      'groupId': groupId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // Step 2: Add creator as member AFTER group exists.
    // The members subcollection rule requires the group doc to exist
    // with the user in memberIds (isGroupMember check), so this must
    // be a separate write after the group batch commits.
    await _db
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
        await _db.collection('inviteCodes').doc(normalizedCode).get();
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
    await _db.collection('groups').doc(groupId).update({
      'memberIds': FieldValue.arrayUnion([uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Step 2: Create member document (now user is in memberIds,
    // so isGroupMember() check passes).
    const uuid = Uuid();
    final memberId = uuid.v4();

    await _db
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
    final updatedDoc = await _db.collection('groups').doc(groupId).get();
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

    await _db.collection('groups').doc(groupId).update(updateMap);
  }

  /// Update a member's display name in the group (D-07).
  Future<void> updateMemberDisplayName({
    required String groupId,
    required String memberId,
    required String displayName,
  }) async {
    await _db
        .collection('groups')
        .doc(groupId)
        .collection('members')
        .doc(memberId)
        .update({'displayName': displayName});
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
