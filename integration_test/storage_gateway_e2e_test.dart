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
///   1. A group member can obtain a signed upload URL, PUT bytes to GCS via
///      that URL, record Firestore metadata, then list the new document back
///      with a pre-issued signed download URL (happy path).
///   2. A non-member (different anonymous uid with no membership row) is
///      rejected by the callable with StorageException.notMember.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late StorageGateway gateway;

  setUpAll(() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    FirebaseFunctions.instanceFor(region: 'us-central1')
        .useFunctionsEmulator('localhost', 5001);
    await FirebaseStorage.instance.useStorageEmulator('localhost', 9199);
    gateway = StorageGateway();
  });

  Future<String> signInAsNewAnonymous() async {
    await FirebaseAuth.instance.signOut();
    final cred = await FirebaseAuth.instance.signInAnonymously();
    return cred.user!.uid;
  }

  test('member uploads a document end-to-end', () async {
    final uid = await signInAsNewAnonymous();
    final db = FirebaseFirestore.instance;
    await db.doc('groups/e2e-g1').set({
      'memberIds': [uid],
      'name': 'E2E',
    });
    await db.doc('groups/e2e-g1/events/e2e-e1').set({
      'groupId': 'e2e-g1',
      'name': 'Trip',
    });

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

    final putResp = await http.put(
      Uri.parse(signed.uploadUrl),
      headers: {'Content-Type': 'text/plain'},
      body: Uint8List.fromList('hello world'.codeUnits),
    );
    expect(putResp.statusCode, inInclusiveRange(200, 299));

    final docId = DateTime.now().millisecondsSinceEpoch.toString();
    await db.doc('groups/e2e-g1/events/e2e-e1/documents/$docId').set({
      'id': docId,
      'fileName': 'hello.txt',
      'mimeType': 'text/plain',
      'storagePath': signed.storagePath,
      'sizeBytes': 11,
      'uploadedBy': uid,
      'uploadedAt': FieldValue.serverTimestamp(),
      'isDeleted': false,
    });

    final docs = await gateway.listDocumentsWithUrls(
      groupId: 'e2e-g1',
      eventId: 'e2e-e1',
    );
    expect(docs, isNotEmpty);
    final justUploaded = docs.firstWhere(
      (d) => d.fields['id'] == docId,
      orElse: () => throw StateError('Uploaded doc not in list'),
    );
    expect(justUploaded.signedUrl, startsWith('http'));
    expect(justUploaded.fields['fileName'], 'hello.txt');
  });

  test('non-member cannot upload', () async {
    final nonMemberUid = await signInAsNewAnonymous();
    final db = FirebaseFirestore.instance;
    // Fresh group where nonMemberUid is NOT listed.
    await db.doc('groups/e2e-g2').set({
      'memberIds': ['some-other-uid'],
      'name': 'E2E-2',
    });
    await db.doc('groups/e2e-g2/events/e2e-e2').set({
      'groupId': 'e2e-g2',
      'name': 'Trip2',
    });

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
