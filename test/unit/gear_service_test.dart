import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/gear/services/gear_service.dart';

void main() {
  group('GearService (Firestore)', () {
    late FakeFirebaseFirestore fakeFirestore;
    late GearService service;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      service = GearService.withFirestore(fakeFirestore);
    });

    const groupId = 'g1';
    const eventId = 'e1';

    group('addGearItem', () {
      test(
        'writes gear item document to groups/{groupId}/events/{eventId}/gear_items',
        () async {
          final item = await service.addGearItem(
            groupId: groupId,
            eventId: eventId,
            itemName: 'Tent',
            isHighPriority: true,
          );

          expect(item.itemName, equals('Tent'));
          expect(item.isHighPriority, isTrue);
          expect(item.isPacked, isFalse);
          expect(item.isDeleted, isFalse);

          final snap = await fakeFirestore
              .collection('groups')
              .doc(groupId)
              .collection('events')
              .doc(eventId)
              .collection('gear_items')
              .doc(item.id)
              .get();

          expect(snap.exists, isTrue);
          expect(snap.data()!['itemName'], equals('Tent'));
          expect(snap.data()!['eventId'], equals(eventId));
          expect(snap.data()!['isDeleted'], isFalse);
        },
      );
    });

    group('watchGearItems', () {
      test(
        'returns a stream of gear items from Firestore subcollection',
        () async {
          await service.addGearItem(
            groupId: groupId,
            eventId: eventId,
            itemName: 'Sleeping Bag',
          );

          final items = await service
              .watchGearItems(groupId, eventId)
              .first;

          expect(items.length, equals(1));
          expect(items.first.itemName, equals('Sleeping Bag'));
          expect(items.first.tripId, equals(eventId));
        },
      );

      test(
        'filters out soft-deleted items (isDeleted=true)',
        () async {
          final item = await service.addGearItem(
            groupId: groupId,
            eventId: eventId,
            itemName: 'Deleted Tent',
          );

          await service.deleteGearItem(
            groupId: groupId,
            eventId: eventId,
            gearItemId: item.id,
          );

          // watchGearItems filters isDeleted=false — deleted item should not appear
          // Note: FakeFirebaseFirestore supports .where() and .orderBy() filtering
          final itemsBefore = await service
              .watchGearItems(groupId, eventId)
              .first;

          expect(itemsBefore, isEmpty);
        },
      );
    });

    group('togglePacked', () {
      test(
        'updates isPacked field on Firestore document',
        () async {
          final item = await service.addGearItem(
            groupId: groupId,
            eventId: eventId,
            itemName: 'Backpack',
          );

          expect(item.isPacked, isFalse);

          await service.togglePacked(
            groupId: groupId,
            eventId: eventId,
            gearItemId: item.id,
            isPacked: true,
          );

          final snap = await fakeFirestore
              .collection('groups')
              .doc(groupId)
              .collection('events')
              .doc(eventId)
              .collection('gear_items')
              .doc(item.id)
              .get();

          expect(snap.data()!['isPacked'], isTrue);
        },
      );
    });

    group('deleteGearItem', () {
      test(
        'uses soft-delete pattern (sets isDeleted=true, deletedAt timestamp)',
        () async {
          final item = await service.addGearItem(
            groupId: groupId,
            eventId: eventId,
            itemName: 'Camp Stove',
          );

          await service.deleteGearItem(
            groupId: groupId,
            eventId: eventId,
            gearItemId: item.id,
          );

          final snap = await fakeFirestore
              .collection('groups')
              .doc(groupId)
              .collection('events')
              .doc(eventId)
              .collection('gear_items')
              .doc(item.id)
              .get();

          expect(snap.data()!['isDeleted'], isTrue);
          expect(snap.data()!['deletedAt'], isNotNull);
          expect(snap.data()!['deletedAt'], isA<String>());
        },
      );
    });
  });
}
