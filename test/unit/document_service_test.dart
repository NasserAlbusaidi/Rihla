import 'package:flutter_test/flutter_test.dart';

// Wave 0 stub: Firestore DocumentService tests.
// Real implementation added in Plan 04-04 (Vault + Documents Migration).

void main() {
  group('DocumentService (Firestore)', () {
    group('watchDocuments', () {
      test(
        'returns a stream of document metadata from Firestore subcollection',
        () {},
        skip: 'Awaiting Plan 04-04: DocumentService Firestore migration',
      );
    });

    group('uploadFile', () {
      test(
        'writes document metadata to groups/{groupId}/events/{eventId}/documents',
        () {},
        skip: 'Awaiting Plan 04-04: DocumentService Firestore migration',
      );

      test(
        'stores Firebase Storage download URL (not Supabase signed URL)',
        () {},
        skip: 'Awaiting Plan 04-04: DocumentService Firestore migration',
      );
    });

    group('deleteDocument', () {
      test(
        'removes Firestore document metadata and Firebase Storage object',
        () {},
        skip: 'Awaiting Plan 04-04: DocumentService Firestore migration',
      );
    });

    group('Document serialization', () {
      test(
        'Document.fromFirestore and toFirestore round-trip produces equivalent object',
        () {},
        skip: 'Awaiting Plan 04-04: DocumentService Firestore migration',
      );
    });
  });
}
