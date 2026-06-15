import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/utils/safe_deserialize.dart';

void main() {
  group('decodeDocsSkippingMalformed (#532)', () {
    Future<List<DocumentSnapshot>> seed(List<Map<String, dynamic>> rows) async {
      final db = FakeFirebaseFirestore();
      for (var i = 0; i < rows.length; i++) {
        await db.collection('c').doc('d$i').set({'i': i, ...rows[i]});
      }
      final snap = await db.collection('c').orderBy('i').get();
      return snap.docs;
    }

    test('keeps the decodable docs and drops the one that throws', () async {
      final docs = await seed([
        {'v': 1},
        {'v': 2}, // this one throws in decode
        {'v': 3},
      ]);

      final out = decodeDocsSkippingMalformed<int>(
        docs,
        (doc) {
          final v = (doc.data() as Map<String, dynamic>)['v'] as int;
          if (v == 2) throw StateError('boom');
          return v;
        },
        context: 'test',
      );

      expect(out, [1, 3]); // middle row skipped, no rethrow, order preserved
    });

    test('returns empty (never rethrows) when every doc throws', () async {
      final docs = await seed([
        {'v': 1},
        {'v': 2},
      ]);

      final out = decodeDocsSkippingMalformed<int>(
        docs,
        (_) => throw StateError('always'),
        context: 'test',
      );

      expect(out, isEmpty);
    });
  });
}
