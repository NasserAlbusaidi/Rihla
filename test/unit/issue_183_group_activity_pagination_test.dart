// Regression tests for #183 — cluster fix-group-activity-pagination-clause-order.
//
// GroupActivityService.fetchActivityPage / fetchActivityPageRaw must apply
// `startAfterDocument` BEFORE `limit`. fake_cloud_firestore evaluates query
// clauses in call order: if `.limit(n)` precedes the cursor, the fake truncates
// to the first n docs and then applies the cursor to that slice, returning the
// wrong/overlapping slice (or throwing "document specified wasn't found").
//
// These tests assert POST-FIX behavior (cursor pages forward correctly, newest
// first, zero overlap across pages). They FAIL against the current clause order
// for the right reason (clause-order semantics), not a typo.
//
// NOTE (merge at GREEN time): the canonical home for these is the existing
// `test/unit/group_activity_service_test.dart`, inside the
// `group('GroupActivityService (Firestore)', ...)` block. Written as a sibling
// file here to avoid clobbering that file during RED. Fold in at GREEN.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/groups/services/group_activity_service.dart';

void main() {
  group('GroupActivityService pagination clause-order (#183)', () {
    late FakeFirebaseFirestore fakeDb;
    late GroupActivityService service;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      service = GroupActivityService.withFirestore(fakeDb);
    });

    const groupId = 'g1';

    Future<void> seedActivity(int n) async {
      for (var i = 0; i < n; i++) {
        // strictly increasing timestamps so ordering has no ties
        final ts = DateTime.utc(2026, 1, 1).add(Duration(seconds: i));
        await fakeDb
            .collection('groups')
            .doc(groupId)
            .collection('activity')
            // doc-id padded only for stable debugging; ordering is by timestamp
            .doc('a${i.toString().padLeft(4, '0')}')
            .set({
          'id': 'a$i',
          'type': 'event_created',
          'actorId': 'u1',
          'actorName': 'Alice',
          'description': 'Event $i',
          'metadata': <String, dynamic>{},
          'timestamp': ts.toIso8601String(),
        });
      }
    }

    test(
      'fetchActivityPageRaw pages forward with startAfter cursor, '
      'newest-first, zero overlap',
      () async {
        await seedActivity(120);

        final p1 = await service.fetchActivityPageRaw(groupId, limit: 50);
        expect(p1.docs, hasLength(50));
        expect(
          p1.docs.first.data()['description'],
          equals('Event 119'),
        ); // newest first

        final p2 = await service.fetchActivityPageRaw(
          groupId,
          startAfter: p1.docs.last,
          limit: 50,
        );
        expect(p2.docs, hasLength(50));

        final p3 = await service.fetchActivityPageRaw(
          groupId,
          startAfter: p2.docs.last,
          limit: 50,
        );
        expect(p3.docs, hasLength(20)); // 120 - 100

        final ids =
            [...p1.docs, ...p2.docs, ...p3.docs].map((d) => d.id).toList();
        expect(ids.toSet(), hasLength(120)); // zero overlap across all pages
      },
    );

    test(
      'fetchActivityPage page 2 via raw cursor has no overlap with page 1',
      () async {
        // seed 12 with strictly-increasing timestamps
        for (var i = 0; i < 12; i++) {
          final ts = DateTime.utc(2026, 2, 1).add(Duration(seconds: i));
          await fakeDb
              .collection('groups')
              .doc(groupId)
              .collection('activity')
              .doc('p${i.toString().padLeft(4, '0')}')
              .set({
            'id': 'p$i',
            'type': 'event_created',
            'actorId': 'u1',
            'actorName': 'Alice',
            'description': 'P$i',
            'metadata': <String, dynamic>{},
            'timestamp': ts.toIso8601String(),
          });
        }

        final raw1 = await service.fetchActivityPageRaw(groupId, limit: 5);
        expect(raw1.docs, hasLength(5));

        final page2 = await service.fetchActivityPage(
          groupId,
          startAfter: raw1.docs.last,
          limit: 5,
        );
        expect(page2, hasLength(5));

        final p1Descrs =
            raw1.docs.map((d) => d.data()['description']).toSet();
        final p2Descrs = page2.map((l) => l.description).toSet();
        expect(
          p1Descrs.intersection(p2Descrs),
          isEmpty,
        ); // zero overlap between page 1 and page 2
      },
    );
  });
}
