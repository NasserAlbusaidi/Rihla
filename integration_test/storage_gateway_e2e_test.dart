import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:safar/core/services/storage_exceptions.dart';
import 'package:safar/core/services/storage_gateway.dart';
import 'package:safar/firebase_options.dart';

/// End-to-end emulator proof for Phase 38's StorageGateway.
///
/// Run with emulators:exec so Firebase boots auth + firestore + functions +
/// storage before this test starts:
///
/// ```
/// firebase emulators:exec --only auth,firestore,functions,storage \
///   "flutter test integration_test/storage_gateway_e2e_test.dart \
///    --dart-define=USE_FIREBASE_EMULATOR=true"
/// ```
///
/// Proves:
///   1. A group member can obtain a signed upload URL, upload bytes through
///      that URL, then list the uploaded object back with a pre-issued signed
///      download URL (happy path).
///   2. A non-member (different anonymous uid with no group/event membership)
///      is rejected by the callable with StorageException.notMember.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late StorageGateway gateway;

  setUpAll(() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform.copyWith(
        projectId: 'rihla-safar-test',
        storageBucket: 'rihla-safar-test.firebasestorage.app',
      ),
    );
    FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).useFunctionsEmulator('localhost', 5001);
    await FirebaseStorage.instance.useStorageEmulator('localhost', 9199);
    gateway = StorageGateway();
  });

  Future<String> signInAsNewAnonymous() async {
    await FirebaseAuth.instance.signOut();
    final cred = await FirebaseAuth.instance.signInAnonymously();
    return cred.user!.uid;
  }

  Future<void> createGroupWithEvent({
    required String groupId,
    required String eventId,
    required String ownerUid,
  }) async {
    final db = FirebaseFirestore.instance;
    final now = Timestamp.now();
    await db.doc('groups/$groupId').set({
      'id': groupId,
      'name': 'E2E',
      'inviteCode': groupId.toUpperCase(),
      'createdBy': ownerUid,
      'memberIds': [ownerUid],
      'currency': 'OMR',
      'createdAt': now,
      'updatedAt': now,
    });
    await db.doc('groups/$groupId/members/$ownerUid').set({
      'id': ownerUid,
      'userId': ownerUid,
      'displayName': 'Owner',
      'role': 'CREATOR',
      'joinedAt': now,
      'isShadow': false,
    });
    await db.doc('groups/$groupId/events/$eventId').set({
      'name': 'Trip',
      'type': 'trip',
      'groupId': groupId,
      'createdBy': ownerUid,
      'participantIds': [ownerUid],
      'participantNames': {ownerUid: 'Owner'},
      'modules': {'ledger': true},
      'startDate': null,
      'endDate': null,
      'isDeleted': false,
      'deletedAt': null,
      'createdAt': now,
      'serverCreatedAt': null,
      'updatedAt': now,
      'description': null,
    });
  }

  test('member uploads a document end-to-end', () async {
    final uid = await signInAsNewAnonymous();
    await createGroupWithEvent(
      groupId: 'e2e-g1',
      eventId: 'e2e-e1',
      ownerUid: uid,
    );

    final signed = await gateway.getSignedUploadUrl(
      bucket: 'documents',
      groupId: 'e2e-g1',
      eventId: 'e2e-e1',
      fileName: 'hello.txt',
      contentType: 'text/plain',
      sizeBytes: 11,
    );
    expect(signed.uploadUrl, startsWith('http'));
    expect(signed.storagePath, startsWith('trip-documents/e2e-e1/'));

    final uploadUri = Uri.parse(signed.uploadUrl);
    final uploadResp = uploadUri.path.startsWith('/upload/storage/v1/')
        ? await http.post(
            uploadUri,
            headers: {'Content-Type': 'text/plain'},
            body: Uint8List.fromList('hello world'.codeUnits),
          )
        : await http.put(
            uploadUri,
            headers: {'Content-Type': 'text/plain'},
            body: Uint8List.fromList('hello world'.codeUnits),
          );
    expect(
      uploadResp.statusCode,
      inInclusiveRange(200, 299),
      reason: uploadResp.body,
    );

    final docs = await gateway.listDocumentsWithUrls(
      groupId: 'e2e-g1',
      eventId: 'e2e-e1',
    );
    expect(docs, isNotEmpty);
    final justUploaded = docs.firstWhere(
      (d) => d.fields['storagePath'] == signed.storagePath,
      orElse: () => throw StateError('Uploaded doc not in list'),
    );
    expect(justUploaded.signedUrl, startsWith('http'));
    expect(justUploaded.fields['id'], signed.storagePath);
    expect(justUploaded.fields['fileName'], endsWith('hello.txt'));
  });

  test('non-member cannot upload', () async {
    final ownerUid = await signInAsNewAnonymous();
    await createGroupWithEvent(
      groupId: 'e2e-g2',
      eventId: 'e2e-e2',
      ownerUid: ownerUid,
    );

    final nonMemberUid = await signInAsNewAnonymous();

    await expectLater(
      gateway.getSignedUploadUrl(
        bucket: 'documents',
        groupId: 'e2e-g2',
        eventId: 'e2e-e2',
        fileName: 'nope.txt',
        contentType: 'text/plain',
        sizeBytes: 4,
      ),
      throwsA(
        isA<StorageException>().having(
          (e) => e.toString(),
          'toString',
          contains('Not a member'),
        ),
      ),
    );
    expect(nonMemberUid, isNotEmpty);
  });
}
