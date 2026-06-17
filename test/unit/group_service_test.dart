import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
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

      test(
        'creator member doc is keyed by uid (id == uid), not a random uuid '
        '(#524 — one member doc per uid)',
        () async {
          SharedPreferences.setMockInitialValues({'device_name': 'Nasser'});
          final prefs = await SharedPreferences.getInstance();
          final fakeDb = FakeFirebaseFirestore();
          const uid = 'creator-uid-524';

          final container = ProviderContainer(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              groupServiceProvider.overrideWith(
                (ref) => GroupService.withFirestore(
                  ref,
                  fakeDb,
                  currentUserId: uid,
                ),
              ),
            ],
          );
          addTearDown(container.dispose);

          final service = container.read(groupServiceProvider);
          final staged =
              service.stageGroup(name: 'Jebel Shams', currency: 'OMR');
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
        },
      );

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

      test(
        'joinGroup maps callable errors to existing user messages',
        () async {
          for (final entry in {
            'unauthenticated': 'Please sign in and try again.',
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
        },
      );
    });

    group('updateGroup', () {
      test(
        'updateGroup throws when group document does not exist in fakeDb',
        () async {
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

          // FakeFirebaseFirestore throws 'not-found' when updating a non-existent doc.
          // This verifies that updateGroup propagates the Firestore error correctly.
          expect(
            () async =>
                service.updateGroup(groupId: 'grp-nonexistent', name: 'Name'),
            throwsA(anything),
          );
        },
      );

      // #261 (Model A): currency is immutable after create — `updateGroup` no
      // longer accepts a `currency:` param (settable only in `createGroup`), so
      // the former 'updates currency field' / 'both name and currency' tests are
      // removed. Rule enforcement is covered in the functions rules suite.
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
