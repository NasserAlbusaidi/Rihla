// Real-service coverage for DisplayNamePropagationService.stage() (#1102).
//
// display_name_reconciliation_1102_test.dart injects a mock
// DisplayNamePropagationService via propagationServiceFactory, so the real
// group/member Firestore discovery + batch.update + batch.commit body in
// stage() is never exercised there. These tests call the REAL stage()
// against a FakeFirebaseFirestore.
//
// stage() reads FirebaseConfig.currentUser?.uid directly with no injection
// seam, so a plain flutter_test run throws [core/no-app] before it ever
// reaches the Firestore work (there is no lib/ constructor param for the uid
// — adding one would be a lib/ change, out of scope for a coverage-only
// PR). To exercise the real body without touching lib/, this file registers
// a minimal fake FirebaseAuthPlatform — the same low-level seam the
// firebase_auth_platform_interface package uses in its own test suite — so
// FirebaseConfig.currentUser resolves to a real (fake) signed-in uid without
// any platform channel or native SDK involved.
//
// FirebaseAuth caches its delegate on first access per app, so the uid is
// fixed once in setUpAll and held constant across every test below; each
// test instead varies the seeded Firestore data.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/services/display_name_propagation_service.dart';

const _uid = 'uid-me';

class _FakeMultiFactorPlatform extends MultiFactorPlatform {
  _FakeMultiFactorPlatform(super.auth);
}

class _FakeUserPlatform extends UserPlatform {
  _FakeUserPlatform(FirebaseAuthPlatform auth, String uid)
    : super(
        auth,
        _FakeMultiFactorPlatform(auth),
        PigeonUserDetails(
          userInfo: PigeonUserInfo(
            uid: uid,
            isAnonymous: true,
            isEmailVerified: false,
          ),
          providerData: const [],
        ),
      );
}

/// Registers as [FirebaseAuthPlatform.instance] so `FirebaseAuth.instance`
/// resolves its delegate to this fake instead of the real method-channel
/// implementation — no native/platform-channel plumbing required.
class _FakeFirebaseAuthPlatform extends FirebaseAuthPlatform {
  _FakeFirebaseAuthPlatform(FirebaseApp app, String uid)
    : super(appInstance: app) {
    _user = _FakeUserPlatform(this, uid);
  }

  UserPlatform? _user;

  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;

  @override
  FirebaseAuthPlatform setInitialValues({
    PigeonUserDetails? currentUser,
    String? languageCode,
  }) => this;

  @override
  UserPlatform? get currentUser => _user;
}

Future<void> _seedGroup(
  FakeFirebaseFirestore db, {
  required String id,
  required List<String> memberIds,
}) {
  return db.collection('groups').doc(id).set({
    'id': id,
    'memberIds': memberIds,
  });
}

Future<void> _seedMember(
  FakeFirebaseFirestore db, {
  required String groupId,
  required String docId,
  required String userId,
  required String displayName,
}) {
  return db
      .collection('groups')
      .doc(groupId)
      .collection('members')
      .doc(docId)
      .set({'userId': userId, 'displayName': displayName});
}

void main() {
  setUpAll(() async {
    setupFirebaseCoreMocks();
    final app = await Firebase.initializeApp();
    FirebaseAuthPlatform.instance = _FakeFirebaseAuthPlatform(app, _uid);
  });

  test(
    'stage() updates member docs matched by the userId FIELD — both a '
    'uid-keyed doc and a uuid-keyed shadow doc — never by the doc id '
    '(the #524/addShadowMember mixed-keying invariant)',
    () async {
      final db = FakeFirebaseFirestore();
      await _seedGroup(db, id: 'g1', memberIds: [_uid, 'other-uid']);
      // Client-created doc keyed by {uid} (post-#524 convention).
      await _seedMember(
        db,
        groupId: 'g1',
        docId: _uid,
        userId: _uid,
        displayName: 'Old Name',
      );
      // Server-minted/legacy doc keyed by an unrelated uuid — matched only
      // via the userId field, never the doc id.
      await _seedMember(
        db,
        groupId: 'g1',
        docId: 'shadow-uuid-abc',
        userId: _uid,
        displayName: 'Old Name',
      );
      // A different member in the same group must be left untouched.
      await _seedMember(
        db,
        groupId: 'g1',
        docId: 'other-uid',
        userId: 'other-uid',
        displayName: 'Someone Else',
      );

      final service = DisplayNamePropagationService.withFirestore(db);
      final staged = await service.stage('New Name');

      expect(staged, isNotNull);
      await staged!.ack;

      final uidKeyed = await db
          .collection('groups')
          .doc('g1')
          .collection('members')
          .doc(_uid)
          .get();
      final uuidKeyed = await db
          .collection('groups')
          .doc('g1')
          .collection('members')
          .doc('shadow-uuid-abc')
          .get();
      final untouched = await db
          .collection('groups')
          .doc('g1')
          .collection('members')
          .doc('other-uid')
          .get();

      expect(uidKeyed.data()!['displayName'], 'New Name');
      expect(uuidKeyed.data()!['displayName'], 'New Name');
      expect(untouched.data()!['displayName'], 'Someone Else');
    },
  );

  test(
    'stage() updates matching members across MULTIPLE groups in one batch',
    () async {
      final db = FakeFirebaseFirestore();
      await _seedGroup(db, id: 'g1', memberIds: [_uid]);
      await _seedGroup(db, id: 'g2', memberIds: [_uid]);
      await _seedMember(
        db,
        groupId: 'g1',
        docId: _uid,
        userId: _uid,
        displayName: 'Old',
      );
      await _seedMember(
        db,
        groupId: 'g2',
        docId: _uid,
        userId: _uid,
        displayName: 'Old',
      );

      final service = DisplayNamePropagationService.withFirestore(db);
      final staged = await service.stage('Fresh Name');
      await staged!.ack;

      for (final gid in ['g1', 'g2']) {
        final doc = await db
            .collection('groups')
            .doc(gid)
            .collection('members')
            .doc(_uid)
            .get();
        expect(doc.data()!['displayName'], 'Fresh Name');
      }
    },
  );

  test(
    'stage() with no groups for the uid stages and commits an empty batch '
    '(empty path)',
    () async {
      final db = FakeFirebaseFirestore();
      await _seedGroup(db, id: 'g-other', memberIds: ['someone-else']);

      final service = DisplayNamePropagationService.withFirestore(db);
      final staged = await service.stage('New Name');

      expect(staged, isNotNull);
      await expectLater(staged!.ack, completes);
    },
  );

  test(
    'stage() on a matched group with no member docs for the uid still '
    'commits without error (empty members path)',
    () async {
      final db = FakeFirebaseFirestore();
      await _seedGroup(db, id: 'g1', memberIds: [_uid]);
      // No members subcollection docs at all for g1.

      final service = DisplayNamePropagationService.withFirestore(db);
      final staged = await service.stage('New Name');

      expect(staged, isNotNull);
      await expectLater(staged!.ack, completes);
    },
  );
}
