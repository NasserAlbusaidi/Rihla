import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/logistics/services/sub_group_service.dart';

void main() {
  group('SubGroupService (Firestore)', () {
    late FakeFirebaseFirestore fakeFirestore;
    late SubGroupService service;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      service = SubGroupService.withFirestore(fakeFirestore);
    });

    const groupId = 'g1';
    const eventId = 'e1';

    group('createSubGroup', () {
      test(
        'writes sub-group document to groups/{groupId}/events/{eventId}/sub_groups',
        () async {
          final subGroup = await service.createSubGroup(
            groupId: groupId,
            eventId: eventId,
            name: 'Car 1',
            type: 'CAR',
            capacity: 5,
          );

          expect(subGroup.name, equals('Car 1'));
          expect(subGroup.type.value, equals('CAR'));
          expect(subGroup.capacity, equals(5));
          expect(subGroup.tripId, equals(eventId));

          final snap = await fakeFirestore
              .collection('groups')
              .doc(groupId)
              .collection('events')
              .doc(eventId)
              .collection('sub_groups')
              .doc(subGroup.id)
              .get();

          expect(snap.exists, isTrue);
          expect(snap.data()!['name'], equals('Car 1'));
          expect(snap.data()!['type'], equals('CAR'));
          expect(snap.data()!['eventId'], equals(eventId));
        },
      );
    });

    group('watchSubGroups', () {
      test(
        'returns a stream of sub-groups from Firestore subcollection',
        () async {
          await service.createSubGroup(
            groupId: groupId,
            eventId: eventId,
            name: 'Room A',
            type: 'ROOM',
          );

          await service.createSubGroup(
            groupId: groupId,
            eventId: eventId,
            name: 'Room B',
            type: 'ROOM',
          );

          final subGroups = await service
              .watchSubGroups(groupId, eventId)
              .first;

          expect(subGroups.length, equals(2));
          final names = subGroups.map((sg) => sg.name).toList();
          expect(names, containsAll(['Room A', 'Room B']));
        },
      );
    });

    group('addMember', () {
      test(
        'writes member document to sub_groups/{subGroupId}/members subcollection',
        () async {
          final subGroup = await service.createSubGroup(
            groupId: groupId,
            eventId: eventId,
            name: 'Team Alpha',
            type: 'TEAM',
          );

          await service.addMember(
            groupId: groupId,
            eventId: eventId,
            subGroupId: subGroup.id,
            participantId: 'p1',
            displayName: 'Alice',
          );

          final membersSnap = await fakeFirestore
              .collection('groups')
              .doc(groupId)
              .collection('events')
              .doc(eventId)
              .collection('sub_groups')
              .doc(subGroup.id)
              .collection('members')
              .get();

          expect(membersSnap.docs.length, equals(1));
          expect(membersSnap.docs.first.data()['participantId'], equals('p1'));
          expect(membersSnap.docs.first.data()['displayName'], equals('Alice'));
        },
      );
    });

    group('removeMember', () {
      test(
        'deletes member document from sub_groups/{subGroupId}/members subcollection',
        () async {
          final subGroup = await service.createSubGroup(
            groupId: groupId,
            eventId: eventId,
            name: 'Team Beta',
            type: 'TEAM',
          );

          await service.addMember(
            groupId: groupId,
            eventId: eventId,
            subGroupId: subGroup.id,
            participantId: 'p2',
            displayName: 'Bob',
          );

          final membersSnap = await fakeFirestore
              .collection('groups')
              .doc(groupId)
              .collection('events')
              .doc(eventId)
              .collection('sub_groups')
              .doc(subGroup.id)
              .collection('members')
              .get();

          expect(membersSnap.docs.length, equals(1));
          final memberId = membersSnap.docs.first.id;

          await service.removeMember(
            groupId: groupId,
            eventId: eventId,
            subGroupId: subGroup.id,
            memberId: memberId,
          );

          final afterSnap = await fakeFirestore
              .collection('groups')
              .doc(groupId)
              .collection('events')
              .doc(eventId)
              .collection('sub_groups')
              .doc(subGroup.id)
              .collection('members')
              .get();

          expect(afterSnap.docs, isEmpty);
        },
      );
    });
  });
}
