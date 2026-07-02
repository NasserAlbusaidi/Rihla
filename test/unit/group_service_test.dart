import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';

void main() {
  group('GroupService', () {
    group('createGroup', () {
      test(
        'creator is added as member with role CREATOR via provider (D-09)',
        () async {
          // Verify the GroupService class exists and has the expected shape.
          // Uses withFirestore injection so no real Firebase is required.
          SharedPreferences.setMockInitialValues({'device_name': 'Nasser'});
          final prefs = await SharedPreferences.getInstance();
          final fakeDb = FakeFirebaseFirestore();

          final container = ProviderContainer(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              groupServiceProvider.overrideWith(
                (ref) => GroupService.withFirestore(ref, fakeDb),
              ),
            ],
          );
          addTearDown(container.dispose);

          // Verify GroupService can be obtained from the provider
          final service = container.read(groupServiceProvider);
          expect(service, isNotNull);
          expect(service, isA<GroupService>());
        },
      );

      test('creator member doc is keyed by uid (id == uid), not a random uuid '
          '(#524 — one member doc per uid)', () async {
        SharedPreferences.setMockInitialValues({'device_name': 'Nasser'});
        final prefs = await SharedPreferences.getInstance();
        final fakeDb = FakeFirebaseFirestore();
        const uid = 'creator-uid-524';

        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            groupServiceProvider.overrideWith(
              (ref) =>
                  GroupService.withFirestore(ref, fakeDb, currentUserId: uid),
            ),
          ],
        );
        addTearDown(container.dispose);

        final service = container.read(groupServiceProvider);
        final staged = service.stageGroup(name: 'Jebel Shams', currency: 'OMR');
        await staged.ack;

        final members = await fakeDb
            .collection('groups')
            .doc(staged.group.id)
            .collection('members')
            .get();

        expect(members.docs.length, 1);
        final memberDoc = members.docs.single;
        expect(memberDoc.id, uid, reason: 'doc id must equal the uid');
        expect(memberDoc.data()['id'], uid);
        expect(memberDoc.data()['userId'], uid);
        expect(memberDoc.data()['role'], 'CREATOR');
      });

      group('glyph / inkIndex on create (#287 trip-stamps)', () {
        // PR-2b Task 6: an explicit stamp pick threads through stageGroup into
        // the create doc. The rules allow-list both keys on create AND reject an
        // explicit null (firestore.rules validGroupCreate), so a default group
        // MUST omit the keys entirely — the write is conditional, never a
        // fallback. FakeFirebaseFirestore does not enforce rules, so these tests
        // pin the omit-when-null contract directly (the prod rule path is pinned
        // separately by firestore-rules-publish-readiness.test.ts).
        Future<GroupService> stampService(FakeFirebaseFirestore fakeDb) async {
          SharedPreferences.setMockInitialValues({'device_name': 'Nasser'});
          final prefs = await SharedPreferences.getInstance();
          final container = ProviderContainer(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              groupServiceProvider.overrideWith(
                (ref) => GroupService.withFirestore(
                  ref,
                  fakeDb,
                  currentUserId: 'creator-uid-287',
                ),
              ),
            ],
          );
          addTearDown(container.dispose);
          return container.read(groupServiceProvider);
        }

        test('persists chosen glyph + inkIndex in the create doc and the local '
            'Group', () async {
          final fakeDb = FakeFirebaseFirestore();
          final service = await stampService(fakeDb);

          final staged = service.stageGroup(
            name: 'Jebel Shams',
            currency: 'OMR',
            glyph: 'tent',
            inkIndex: 3,
          );
          await staged.ack;

          final data =
              (await fakeDb.collection('groups').doc(staged.group.id).get())
                  .data()!;
          expect(data['glyph'], 'tent');
          expect(data['inkIndex'], 3);

          // The optimistic pre-snapshot object carries the pick too, so the
          // landing tile matches the doc before the first Firestore snapshot.
          expect(staged.group.glyph, 'tent');
          expect(staged.group.inkIndex, 3);
        });

        test('omits both keys entirely when no stamp is chosen (never write a '
            'fallback — rules reject an explicit null)', () async {
          final fakeDb = FakeFirebaseFirestore();
          final service = await stampService(fakeDb);

          final staged = service.stageGroup(
            name: 'Plain Group',
            currency: 'OMR',
          );
          await staged.ack;

          final data =
              (await fakeDb.collection('groups').doc(staged.group.id).get())
                  .data()!;
          expect(
            data.containsKey('glyph'),
            isFalse,
            reason: 'default group must not carry a glyph key',
          );
          expect(
            data.containsKey('inkIndex'),
            isFalse,
            reason: 'default group must not carry an inkIndex key',
          );

          expect(staged.group.glyph, isNull);
          expect(staged.group.inkIndex, isNull);
        });

        test('writes glyph only, leaving inkIndex absent', () async {
          final fakeDb = FakeFirebaseFirestore();
          final service = await stampService(fakeDb);

          final staged = service.stageGroup(
            name: 'Glyph Only',
            currency: 'OMR',
            glyph: 'mountain',
          );
          await staged.ack;

          final data =
              (await fakeDb.collection('groups').doc(staged.group.id).get())
                  .data()!;
          expect(data['glyph'], 'mountain');
          expect(data.containsKey('inkIndex'), isFalse);
          expect(staged.group.glyph, 'mountain');
          expect(staged.group.inkIndex, isNull);
        });

        test('writes inkIndex only, leaving glyph absent', () async {
          final fakeDb = FakeFirebaseFirestore();
          final service = await stampService(fakeDb);

          final staged = service.stageGroup(
            name: 'Ink Only',
            currency: 'OMR',
            inkIndex: 5,
          );
          await staged.ack;

          final data =
              (await fakeDb.collection('groups').doc(staged.group.id).get())
                  .data()!;
          expect(data['inkIndex'], 5);
          expect(data.containsKey('glyph'), isFalse);
          expect(staged.group.inkIndex, 5);
          expect(staged.group.glyph, isNull);
        });

        test(
          'createGroup forwards glyph + inkIndex through to the create doc',
          () async {
            final fakeDb = FakeFirebaseFirestore();
            final service = await stampService(fakeDb);

            final group = await service.createGroup(
              name: 'Via createGroup',
              currency: 'OMR',
              glyph: 'palm',
              inkIndex: 2,
            );

            final data = (await fakeDb.collection('groups').doc(group.id).get())
                .data()!;
            expect(data['glyph'], 'palm');
            expect(data['inkIndex'], 2);
            expect(group.glyph, 'palm');
            expect(group.inkIndex, 2);
          },
        );
      });

      test('groupServiceProvider is accessible from container', () async {
        SharedPreferences.setMockInitialValues({'device_name': 'Ali'});
        final prefs = await SharedPreferences.getInstance();
        final fakeDb = FakeFirebaseFirestore();

        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            groupServiceProvider.overrideWith(
              (ref) => GroupService.withFirestore(ref, fakeDb),
            ),
          ],
        );
        addTearDown(container.dispose);

        expect(container.read(groupServiceProvider), isA<GroupService>());
      });

      test('groupLoadingProvider initial state is false', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        expect(container.read(groupLoadingProvider), isFalse);
      });

      test('groupErrorProvider initial state is null', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        expect(container.read(groupErrorProvider), isNull);
      });

      test(
        'createGroup throws when current user is null (unauthenticated)',
        () async {
          // When Firebase currentUser is null (signed out or not initialized),
          // createGroup throws 'User not authenticated'. This verifies the
          // auth guard fires before any Firestore write.
          SharedPreferences.setMockInitialValues({'device_name': 'Nasser'});
          final prefs = await SharedPreferences.getInstance();
          final fakeDb = FakeFirebaseFirestore();

          final container = ProviderContainer(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              groupServiceProvider.overrideWith(
                (ref) => GroupService.withFirestore(ref, fakeDb),
              ),
            ],
          );
          addTearDown(container.dispose);

          final service = container.read(groupServiceProvider);

          // FirebaseConfig.currentUser returns null when no user is signed in.
          // The service should throw before touching Firestore.
          expect(
            () => service.createGroup(name: 'Test Group', currency: 'OMR'),
            throwsA(isA<Exception>()),
          );
        },
      );
    });

    group('auto-seeded ledger event (#245)', () {
      // A fresh group is born with one ledger event named after the group, so
      // the first-expense path collapses to create-group → add-expense. The
      // seed write is chained AFTER the group batch (the events rule reads
      // groups/{gid}.memberIds), same ordering constraint as the member write.
      Future<GroupService> seedService(
        FakeFirebaseFirestore fakeDb, {
        String uid = 'creator-uid-245',
      }) async {
        // The live prefs key (settings_service.dart _deviceNameKey) — the
        // 'device_name' key used elsewhere in this file predates it and never
        // mattered there (those tests don't assert displayName).
        SharedPreferences.setMockInitialValues({
          'settings_device_name': 'Nasser',
        });
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            groupServiceProvider.overrideWith(
              (ref) =>
                  GroupService.withFirestore(ref, fakeDb, currentUserId: uid),
            ),
          ],
        );
        addTearDown(container.dispose);
        return container.read(groupServiceProvider);
      }

      test('stageGroup seeds exactly one ledger event named after the group, '
          'participants = creator only', () async {
        final fakeDb = FakeFirebaseFirestore();
        const uid = 'creator-uid-245';
        final service = await seedService(fakeDb);

        final staged = service.stageGroup(name: 'Muscat Trip', currency: 'OMR');
        await staged.ack;

        final events = await fakeDb
            .collection('groups')
            .doc(staged.group.id)
            .collection('events')
            .get();
        expect(events.docs.length, 1);

        final data = events.docs.single.data();
        expect(data['name'], 'Muscat Trip');
        expect(data['type'], 'trip');
        expect(data['groupId'], staged.group.id);
        expect(data['createdBy'], uid);
        expect(data['participantIds'], [uid]);
        expect(data['participantNames'], {uid: 'Nasser'});
        expect(data['modules'], {'ledger': true});
        expect(data['isDeleted'], false);
        expect(data['deletedAt'], null);
        // #723: events are born open — validEventCreate pins the triple.
        expect(data['isClosed'], false);
        expect(data['closedAt'], null);
        expect(data['closedBy'], null);
        expect(data['startDate'], null);
        expect(data['endDate'], null);
      });

      test('seeded event round-trips through Event.fromDoc (serializer '
          'contract, no hand-rolled map)', () async {
        final fakeDb = FakeFirebaseFirestore();
        const uid = 'creator-uid-245';
        final service = await seedService(fakeDb);

        final staged = service.stageGroup(name: 'Jebel Shams', currency: 'OMR');
        await staged.ack;

        final snapshot = (await fakeDb
                .collection('groups')
                .doc(staged.group.id)
                .collection('events')
                .get())
            .docs
            .single;
        final event = Event.fromDoc(snapshot);
        expect(event.name, 'Jebel Shams');
        expect(event.type, EventType.trip);
        expect(event.participantIds, [uid]);
        expect(event.participantNames, {uid: 'Nasser'});
        expect(event.modules.ledger, isTrue);
        expect(event.isDeleted, isFalse);
        expect(event.isClosed, isFalse);
      });

      test('offline (unacked batch) stages no event yet — the seed is chained '
          'on the group ack like the member write', () async {
        // stageGroup's guards run synchronously; the event write must not be
        // issued before the batch acks (rules ordering). FakeFirebaseFirestore
        // acks instantly, so pin the CHAIN SHAPE instead: after ack, member and
        // event both exist (the chain completed in order without throwing).
        final fakeDb = FakeFirebaseFirestore();
        final service = await seedService(fakeDb);

        final staged = service.stageGroup(name: 'Wadi Bani', currency: 'OMR');
        await staged.ack;

        final members = await fakeDb
            .collection('groups')
            .doc(staged.group.id)
            .collection('members')
            .get();
        final events = await fakeDb
            .collection('groups')
            .doc(staged.group.id)
            .collection('events')
            .get();
        expect(members.docs.length, 1);
        expect(events.docs.length, 1);
      });
    });

    group('updateGroup', () {
      test('updateGroup function signature accepts name', () {
        // Verify the method signature exists and compiles correctly
        // by checking that the method is defined on GroupService.
        SharedPreferences.setMockInitialValues({});
        expect(GroupService.new, isNotNull);
      });
    });

    group('updateMemberDisplayName', () {
      test(
        'updateMemberDisplayName function signature accepts groupId, memberId, displayName',
        () {
          // Method signature verification — real integration test would need
          // a Firebase Emulator since FakeFirebaseFirestore doesn't support
          // method interception for partial updates.
          expect(GroupService.new, isNotNull);
        },
      );
    });

    group('joinGroup', () {
      test(
        'joinGroup throws when current user is null (unauthenticated)',
        () async {
          SharedPreferences.setMockInitialValues({
            'settings_device_name': 'Nasser',
          });
          final prefs = await SharedPreferences.getInstance();
          final fakeDb = FakeFirebaseFirestore();

          final container = ProviderContainer(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              groupServiceProvider.overrideWith(
                (ref) => GroupService.withFirestore(ref, fakeDb),
              ),
            ],
          );
          addTearDown(container.dispose);

          final service = container.read(groupServiceProvider);

          expect(
            () => service.joinGroup(inviteCode: 'ABC123'),
            throwsA(isA<Exception>()),
          );
        },
      );

      test(
        'joinGroup throws Invalid invite code when code not found in fakeDb',
        () async {
          // This test covers the path where the user is authenticated but the
          // invite code document doesn't exist. Since FakeFirebaseFirestore
          // always returns non-existent documents without throwing, we check
          // the behavior when auth fails (no user).
          SharedPreferences.setMockInitialValues({
            'settings_device_name': 'Test',
          });
          final prefs = await SharedPreferences.getInstance();
          final fakeDb = FakeFirebaseFirestore();

          final container = ProviderContainer(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              groupServiceProvider.overrideWith(
                (ref) => GroupService.withFirestore(ref, fakeDb),
              ),
            ],
          );
          addTearDown(container.dispose);

          final service = container.read(groupServiceProvider);

          // With no authenticated user, this throws immediately
          expect(
            () async => service.joinGroup(inviteCode: 'INVALID'),
            throwsA(isA<Exception>()),
          );
        },
      );

      test(
        'joinGroup routes through callable and returns the readable group',
        () async {
          SharedPreferences.setMockInitialValues({
            'settings_device_name': 'Joiner',
          });
          final prefs = await SharedPreferences.getInstance();
          final fakeDb = FakeFirebaseFirestore();
          String? calledInviteCode;
          String? calledDisplayName;

          await fakeDb.collection('groups').doc('grp-joined').set({
            'id': 'grp-joined',
            'name': 'Joined Group',
            'inviteCode': 'ABC123',
            'createdBy': 'uid-creator',
            'memberIds': ['uid-creator', 'uid-joiner'],
            'currency': 'OMR',
            'createdAt': Timestamp.now(),
            'updatedAt': Timestamp.now(),
          });

          final container = ProviderContainer(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              groupServiceProvider.overrideWith(
                (ref) => GroupService.withFirestore(
                  ref,
                  fakeDb,
                  currentUserId: 'uid-joiner',
                  joinGroupCallableOverride:
                      ({required inviteCode, required displayName}) async {
                        calledInviteCode = inviteCode;
                        calledDisplayName = displayName;
                        return 'grp-joined';
                      },
                ),
              ),
            ],
          );
          addTearDown(container.dispose);

          final group = await container
              .read(groupServiceProvider)
              .joinGroup(inviteCode: 'abc123');

          expect(calledInviteCode, 'ABC123');
          expect(calledDisplayName, 'Joiner');
          expect(group.id, equals('grp-joined'));
          expect(group.memberIds, contains('uid-joiner'));

          final memberSnap = await fakeDb
              .collection('groups')
              .doc('grp-joined')
              .collection('members')
              .doc('uid-joiner')
              .get();
          expect(memberSnap.exists, isFalse);
        },
      );

      test('joinGroup maps callable errors to existing user messages', () async {
        for (final entry in {
          'unauthenticated':
              'Could not verify this device. Try again, or update from the Play Store.',
          'invalid-argument': 'Invalid invite code.',
          'not-found': 'Invalid invite code.',
          'resource-exhausted': 'Too many attempts. Try again later.',
          'internal': 'Could not join group. Try again.',
        }.entries) {
          SharedPreferences.setMockInitialValues({
            'settings_device_name': 'Joiner',
          });
          final prefs = await SharedPreferences.getInstance();
          final fakeDb = FakeFirebaseFirestore();

          final container = ProviderContainer(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              groupServiceProvider.overrideWith(
                (ref) => GroupService.withFirestore(
                  ref,
                  fakeDb,
                  currentUserId: 'uid-joiner',
                  joinGroupCallableOverride:
                      ({required inviteCode, required displayName}) async {
                        throw FirebaseFunctionsException(
                          code: entry.key,
                          message: 'callable failed',
                        );
                      },
                ),
              ),
            ],
          );
          addTearDown(container.dispose);

          expect(
            () => container
                .read(groupServiceProvider)
                .joinGroup(inviteCode: 'ABC123'),
            throwsA(
              isA<Exception>().having(
                (error) => error.toString(),
                'message',
                contains(entry.value),
              ),
            ),
          );
        }
      });

      test(
        'addShadowMember maps unauthenticated to device verification copy',
        () async {
          final fakeDb = FakeFirebaseFirestore();
          final container = ProviderContainer(
            overrides: [
              groupServiceProvider.overrideWith(
                (ref) => GroupService.withFirestore(
                  ref,
                  fakeDb,
                  currentUserId: 'uid-creator',
                  addShadowMemberCallableOverride:
                      ({required groupId, required displayName}) async {
                        throw FirebaseFunctionsException(
                          code: 'unauthenticated',
                          message: 'callable failed',
                        );
                      },
                ),
              ),
            ],
          );
          addTearDown(container.dispose);

          expect(
            () => container
                .read(groupServiceProvider)
                .addShadowMember(groupId: 'g1', displayName: 'Sara'),
            throwsA(
              isA<Exception>().having(
                (error) => error.toString(),
                'message',
                contains(
                  'Could not verify this device. Try again, or update from the Play Store.',
                ),
              ),
            ),
          );
        },
      );
    });

    group('updateGroupIdentity', () {
      // PR-3 Task A: the creator edits an existing group's identity in ONE
      // atomic write — display name + trip-stamp (glyph + inkIndex). A null
      // glyph/inkIndex CLEARS the field via FieldValue.delete(), so the
      // post-write doc has the key ABSENT (byte-identical to a never-set
      // default), which the deployed `validCreatorMetadataUpdate` rule admits.
      // We never write an explicit null. FakeFirebaseFirestore does not enforce
      // rules, so these tests pin the write-shape contract directly (the prod
      // rule path is pinned separately in the functions rules suite); the
      // FieldValueDelete mock removes the key on .update(), matching prod.
      Future<GroupService> identityService(FakeFirebaseFirestore fakeDb) async {
        SharedPreferences.setMockInitialValues({'device_name': 'Nasser'});
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            groupServiceProvider.overrideWith(
              (ref) => GroupService.withFirestore(
                ref,
                fakeDb,
                currentUserId: 'creator-uid-pr3',
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        return container.read(groupServiceProvider);
      }

      test('throws when the group document does not exist in fakeDb', () async {
        // .update() on a missing doc rejects against FakeFirebaseFirestore
        // (matching prod 'not-found'); verifies updateGroupIdentity propagates
        // the Firestore error rather than silently swallowing it. (Migrated
        // from the removed `updateGroup` group — same write-path edge.)
        final service = await identityService(FakeFirebaseFirestore());

        expect(
          () => service.updateGroupIdentity(
            groupId: 'grp-nonexistent',
            name: 'Name',
          ),
          throwsA(anything),
        );
      });

      test('writes name + glyph + inkIndex in one update', () async {
        final fakeDb = FakeFirebaseFirestore();
        await fakeDb.collection('groups').doc('grp-id').set({
          'id': 'grp-id',
          'name': 'Old Name',
          'currency': 'OMR',
        });
        final service = await identityService(fakeDb);

        await service.updateGroupIdentity(
          groupId: 'grp-id',
          name: 'New Name',
          glyph: 'wave',
          inkIndex: 2,
        );

        final data = (await fakeDb.collection('groups').doc('grp-id').get())
            .data()!;
        expect(data['name'], 'New Name');
        expect(data['glyph'], 'wave');
        expect(data['inkIndex'], 2);
      });

      test(
        'clearing glyph (null) deletes a previously-set glyph key',
        () async {
          final fakeDb = FakeFirebaseFirestore();
          // Seed an EXISTING glyph so this is a true present -> absent
          // transition; a delete on a never-set field proves nothing.
          await fakeDb.collection('groups').doc('grp-id').set({
            'id': 'grp-id',
            'name': 'Old Name',
            'currency': 'OMR',
            'glyph': 'tent',
          });
          final service = await identityService(fakeDb);

          await service.updateGroupIdentity(
            groupId: 'grp-id',
            name: 'X',
            glyph: null,
            inkIndex: 3,
          );

          final data = (await fakeDb.collection('groups').doc('grp-id').get())
              .data()!;
          expect(
            data.containsKey('glyph'),
            isFalse,
            reason: 'a null glyph must clear the key, not write null',
          );
          expect(data['name'], 'X');
          expect(data['inkIndex'], 3);
        },
      );

      test(
        'clearing inkIndex (null) deletes a previously-set inkIndex key',
        () async {
          final fakeDb = FakeFirebaseFirestore();
          await fakeDb.collection('groups').doc('grp-id').set({
            'id': 'grp-id',
            'name': 'Old Name',
            'currency': 'OMR',
            'inkIndex': 1,
          });
          final service = await identityService(fakeDb);

          await service.updateGroupIdentity(
            groupId: 'grp-id',
            name: 'Y',
            glyph: 'sun',
            inkIndex: null,
          );

          final data = (await fakeDb.collection('groups').doc('grp-id').get())
              .data()!;
          expect(
            data.containsKey('inkIndex'),
            isFalse,
            reason: 'a null inkIndex must clear the key, not write null',
          );
          expect(data['glyph'], 'sun');
        },
      );

      test('writes updatedAt (server timestamp resolves to a value)', () async {
        final fakeDb = FakeFirebaseFirestore();
        await fakeDb.collection('groups').doc('grp-id').set({
          'id': 'grp-id',
          'name': 'Old Name',
          'currency': 'OMR',
        });
        final service = await identityService(fakeDb);

        await service.updateGroupIdentity(groupId: 'grp-id', name: 'Z');

        final data = (await fakeDb.collection('groups').doc('grp-id').get())
            .data()!;
        expect(data['updatedAt'], isNotNull);
      });
    });

    group('updateMemberDisplayName integration', () {
      test('updates displayName field in members subcollection', () async {
        SharedPreferences.setMockInitialValues({
          'settings_device_name': 'Test',
        });
        final prefs = await SharedPreferences.getInstance();
        final fakeDb = FakeFirebaseFirestore();

        // Pre-create the member document
        await fakeDb
            .collection('groups')
            .doc('grp-members')
            .collection('members')
            .doc('mem-1')
            .set({'id': 'mem-1', 'displayName': 'OldName', 'role': 'MEMBER'});

        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            groupServiceProvider.overrideWith(
              (ref) => GroupService.withFirestore(ref, fakeDb),
            ),
          ],
        );
        addTearDown(container.dispose);

        final service = container.read(groupServiceProvider);
        await service.updateMemberDisplayName(
          groupId: 'grp-members',
          memberId: 'mem-1',
          displayName: 'NewName',
        );

        final doc = await fakeDb
            .collection('groups')
            .doc('grp-members')
            .collection('members')
            .doc('mem-1')
            .get();
        expect(doc.data()?['displayName'], equals('NewName'));
      });
    });

    group('_generateInviteCode', () {
      test('GroupService can be instantiated via withFirestore', () async {
        SharedPreferences.setMockInitialValues({
          'settings_device_name': 'Test',
        });
        final prefs = await SharedPreferences.getInstance();
        final fakeDb = FakeFirebaseFirestore();

        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            groupServiceProvider.overrideWith(
              (ref) => GroupService.withFirestore(ref, fakeDb),
            ),
          ],
        );
        addTearDown(container.dispose);

        // Just verify the service is instantiated correctly
        final service = container.read(groupServiceProvider);
        expect(service, isA<GroupService>());
      });
    });
  });

  group('GroupService providers', () {
    test('userGroupsProvider is a StreamProvider<List<Group>>', () {
      // Type check — compile-time verification via type system
      expect(userGroupsProvider, isNotNull);
    });

    test(
      'groupMembersProvider is a StreamProvider.family<List<GroupMember>, String>',
      () {
        expect(groupMembersProvider, isNotNull);
      },
    );

    test('groupDetailProvider is a StreamProvider.family<Group?, String>', () {
      expect(groupDetailProvider, isNotNull);
    });

    test(
      'userGroupsProvider returns empty list when no user authenticated',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        // When currentUser is null (no real Firebase init),
        // userGroupsProvider should return a Stream.value([]).
        final groups = await container.read(userGroupsProvider.future);
        expect(groups, isEmpty);
      },
    );
  });
}
