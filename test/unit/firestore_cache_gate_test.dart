import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/services/firestore_cache_gate.dart';

void main() {
  test(
    'FirebaseFirestoreCacheGate delegates clearPersistence to Firestore',
    () async {
      final firestore = FakeFirebaseFirestore();
      final gate = FirebaseFirestoreCacheGate(firestore);

      await expectLater(gate.clearPersistence(), completes);
    },
  );
}
