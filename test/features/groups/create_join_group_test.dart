import 'package:cloud_functions/cloud_functions.dart';
import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/shared/widgets/r_icon_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/providers/balance_aggregate_freshness_provider.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/notification_prompt.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/widgets/group_stamp_picker.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/groups/screens/create_group_screen.dart';
import 'package:safar/features/groups/screens/group_settings_screen.dart';
import 'package:safar/features/groups/screens/join_group_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';
import 'package:safar/shared/widgets/skeleton_loader.dart';

// ---------------------------------------------------------------------------
// CreateGroupScreen tests
// ---------------------------------------------------------------------------

/// #288: the create flow fires the natural-moment permission prompt after the
/// share sheet is dismissed. These tests never dismiss it, but a no-op keeps the
/// flow off any platform channel regardless.
class _NoopPrompt implements NotificationPrompt {
  @override
  Future<void> maybePrompt() async {}
}

/// #818: relocated from durable_gate_wiring_test.dart — a bare Mock lets the
/// gate-removal pins assert `joinGroup` directly without a FakeFirebaseFirestore
/// round-trip.
class _MockGroupService extends Mock implements GroupService {}

Group _gateRemovalGroup() => Group(
  id: 'g1',
  name: 'Trip',
  inviteCode: 'ABCDEF',
  createdBy: 'u1',
  memberIds: const ['u1'],
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  group('CreateGroupScreen', () {
    setUpAll(() {
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'Test User',
      });
    });

    Future<Widget> buildCreateScreen({
      bool loading = false,
      Locale locale = const Locale('en'),
    }) async {
      final prefs = await SharedPreferences.getInstance();
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          groupLoadingProvider.overrideWith((ref) => loading),
          groupErrorProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const CreateGroupScreen(),
        ),
      );
    }

    Future<Widget> buildCreateRoute() async {
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'Test User',
      });
      final prefs = await SharedPreferences.getInstance();
      final router = GoRouter(
        initialLocation: '/create-group',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const Scaffold(body: Text('Home')),
          ),
          GoRoute(
            path: '/create-group',
            builder: (context, state) => const CreateGroupScreen(),
          ),
        ],
      );
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          groupLoadingProvider.overrideWith((ref) => false),
          groupErrorProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      );
    }

    testWidgets('renders top bar with New group title', (tester) async {
      await tester.pumpWidget(await buildCreateScreen());
      await tester.pump();
      expect(find.text('New group'), findsOneWidget);
    });

    testWidgets('renders Create Group wireframe content', (tester) async {
      await tester.pumpWidget(await buildCreateScreen());
      await tester.pump();
      expect(find.text("Who's coming along?"), findsOneWidget);
      expect(
        find.text(
          'A group is a circle of people you share expenses with — a household, a travel crew, a project team.',
        ),
        findsOneWidget,
      );
      expect(find.byType(GroupStampPicker), findsOneWidget);
      expect(find.text('Default currency'), findsOneWidget);
      expect(find.text('OMR'), findsOneWidget);
      expect(find.text("You're the creator."), findsOneWidget);
    });

    testWidgets('#261: currency picker → selecting USD updates the field', (
      tester,
    ) async {
      await tester.pumpWidget(await buildCreateScreen());
      await tester.pumpAndSettle();
      // Defaults to OMR.
      expect(find.text('OMR'), findsOneWidget);

      // Open the picker (tappable field). The trip-stamp picker (#287) makes
      // the form taller than the 600px test viewport, so scroll the field into
      // view before tapping.
      await tester.ensureVisible(find.byKey(GroupKeys.currencyField));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GroupKeys.currencyField));
      await tester.pumpAndSettle();
      expect(find.text('Currency'), findsOneWidget); // sheet title

      // Pick USD (tile title = localized name).
      await tester.tap(find.text('US dollar'));
      await tester.pumpAndSettle();

      // The field now shows USD; OMR is gone.
      expect(find.text('USD'), findsOneWidget);
      expect(find.text('OMR'), findsNothing);
    });

    testWidgets(
      '#261/#383: picker→create persists the SELECTED currency (USD) to '
      'Firestore, not hardcoded OMR',
      (tester) async {
        // #383 Box 2: no test asserted that createGroup(currency:) writes a
        // non-OMR currency. A real GroupService over FakeFirebaseFirestore lets
        // us read back the persisted doc and prove the picker selection threads
        // all the way through createGroup's write-map.
        SharedPreferences.setMockInitialValues({
          'settings_device_name': 'Test User',
        });
        final prefs = await SharedPreferences.getInstance();
        final fakeDb = FakeFirebaseFirestore();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              notificationPromptProvider.overrideWithValue(_NoopPrompt()),
              groupServiceProvider.overrideWith(
                (ref) => GroupService.withFirestore(
                  ref,
                  fakeDb,
                  currentUserId: 'uid-creator',
                ),
              ),
              // #520: the create path reads connectivityProvider; timer-free.
              connectivityProvider.overrideWith(
                (ref) => ConnectivityNotifier(startPeriodicChecks: false),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const CreateGroupScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Pick USD in the currency sheet. Scroll the field into view first —
        // the #287 stamp picker pushes it below the 600px test viewport.
        await tester.ensureVisible(find.byKey(GroupKeys.currencyField));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(GroupKeys.currencyField));
        await tester.pumpAndSettle();
        await tester.tap(find.text('US dollar'));
        await tester.pumpAndSettle();
        expect(find.text('USD'), findsOneWidget);

        // Fill the required fields and create.
        await tester.enterText(find.byKey(GroupKeys.groupNameInput), 'Trip');
        await tester.enterText(
          find.byKey(GroupKeys.deviceNameInput),
          'Test User',
        );
        await tester.pump();
        await tester.tap(find.byKey(GroupKeys.createGroupButton));
        await tester.pumpAndSettle(); // create resolves → share sheet appears

        // The persisted group doc carries the picked currency, not 'OMR'.
        final groups = await fakeDb.collection('groups').get();
        expect(groups.docs.length, 1, reason: 'exactly one group created');
        expect(groups.docs.first.data()['currency'], 'USD');
      },
    );

    testWidgets(
      '#287: selecting an ink + symbol persists glyph/inkIndex on create',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'settings_device_name': 'Test User',
        });
        final prefs = await SharedPreferences.getInstance();
        final fakeDb = FakeFirebaseFirestore();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              notificationPromptProvider.overrideWithValue(_NoopPrompt()),
              groupServiceProvider.overrideWith(
                (ref) => GroupService.withFirestore(
                  ref,
                  fakeDb,
                  currentUserId: 'uid-creator',
                ),
              ),
              connectivityProvider.overrideWith(
                (ref) => ConnectivityNotifier(startPeriodicChecks: false),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const CreateGroupScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Pick ink swatch index 2 and the 'palm' symbol (kGroupGlyphIds[2]).
        await tester.tap(find.byKey(const Key('stampInk_2')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('stampSym_palm')));
        await tester.pump();

        await tester.enterText(find.byKey(GroupKeys.groupNameInput), 'Trip');
        await tester.enterText(
          find.byKey(GroupKeys.deviceNameInput),
          'Test User',
        );
        await tester.pump();
        await tester.tap(find.byKey(GroupKeys.createGroupButton));
        await tester.pumpAndSettle();

        final groups = await fakeDb.collection('groups').get();
        expect(groups.docs.length, 1, reason: 'exactly one group created');
        final data = groups.docs.first.data();
        expect(data['glyph'], 'palm');
        expect(data['inkIndex'], 2);
      },
    );

    testWidgets(
      '#287: creating without touching the picker omits glyph/inkIndex '
      '(monogram default)',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'settings_device_name': 'Test User',
        });
        final prefs = await SharedPreferences.getInstance();
        final fakeDb = FakeFirebaseFirestore();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              notificationPromptProvider.overrideWithValue(_NoopPrompt()),
              groupServiceProvider.overrideWith(
                (ref) => GroupService.withFirestore(
                  ref,
                  fakeDb,
                  currentUserId: 'uid-creator',
                ),
              ),
              connectivityProvider.overrideWith(
                (ref) => ConnectivityNotifier(startPeriodicChecks: false),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const CreateGroupScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(GroupKeys.groupNameInput), 'Trip');
        await tester.enterText(
          find.byKey(GroupKeys.deviceNameInput),
          'Test User',
        );
        await tester.pump();
        await tester.tap(find.byKey(GroupKeys.createGroupButton));
        await tester.pumpAndSettle();

        final groups = await fakeDb.collection('groups').get();
        expect(groups.docs.length, 1, reason: 'exactly one group created');
        final data = groups.docs.first.data();
        // validGroupCreate REJECTS explicit null — defaults must omit the keys.
        expect(data.containsKey('glyph'), isFalse);
        expect(data.containsKey('inkIndex'), isFalse);
      },
    );

    testWidgets('renders Group Name label and hint', (tester) async {
      await tester.pumpWidget(await buildCreateScreen());
      await tester.pump();
      expect(find.text('Group Name'), findsOneWidget);
      expect(find.text('e.g. Family trip'), findsOneWidget);
    });

    testWidgets('renders Your name label with global-name helper (#413)', (
      tester,
    ) async {
      await tester.pumpWidget(await buildCreateScreen());
      await tester.pump();
      expect(find.text('Your name'), findsOneWidget);
      expect(
        find.text(
          'Shown in all your groups. Changing it anywhere updates it everywhere.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders Arabic labels and required-name error', (
      tester,
    ) async {
      await tester.pumpWidget(
        await buildCreateScreen(locale: const Locale('ar')),
      );
      await tester.pump();

      expect(find.text('اسم المجموعة'), findsOneWidget);
      expect(find.text('اسمك'), findsOneWidget);

      await tester.tap(find.text('إنشاء'));
      await tester.pumpAndSettle();

      expect(find.text('لا يمكن أن يكون الاسم فارغًا.'), findsOneWidget);
    });

    testWidgets('pre-fills display name from settings', (tester) async {
      // The device name is seeded in setUpAll via SharedPreferences mock.
      // The controller text is set lazily on first build when _didInitName=false.
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'Test User',
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            groupLoadingProvider.overrideWith((ref) => false),
            groupErrorProvider.overrideWith((ref) => null),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const CreateGroupScreen(),
          ),
        ),
      );
      await tester.pump();
      // Device name from SharedPreferences ('Test User') should appear in the
      // display name controller.
      expect(find.text('Test User'), findsOneWidget);
    });

    testWidgets('renders top-bar Create action', (tester) async {
      await tester.pumpWidget(await buildCreateScreen());
      await tester.pump();
      expect(find.text('Create'), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator when loading is true', (
      tester,
    ) async {
      // LoadingButton shows CircularProgressIndicator when isLoading=true,
      // not the label text.
      await tester.pumpWidget(await buildCreateScreen(loading: true));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('validates group name is required on submit', (tester) async {
      await tester.pumpWidget(await buildCreateScreen());
      await tester.pump();

      // Tap Create without filling the group name field
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text("Name can't be empty."), findsOneWidget);
    });

    testWidgets('group-name error clears when a valid name is typed (#680)', (
      tester,
    ) async {
      await tester.pumpWidget(await buildCreateScreen());
      await tester.pump();

      // Submit with an empty group name → validation error appears.
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.text("Name can't be empty."), findsOneWidget);

      // Type a valid group name. With autovalidateMode.onUserInteraction the
      // form re-validates on input, so the stale error must clear WITHOUT
      // re-submitting (the device-name field is pre-filled and valid).
      await tester.enterText(
        find.byKey(GroupKeys.groupNameInput),
        'Beach Trip',
      );
      await tester.pumpAndSettle();

      expect(find.text("Name can't be empty."), findsNothing);
    });

    testWidgets('validates display name is required on submit', (tester) async {
      SharedPreferences.setMockInitialValues({'device_name': ''});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            groupLoadingProvider.overrideWith((ref) => false),
            groupErrorProvider.overrideWith((ref) => null),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const CreateGroupScreen(),
          ),
        ),
      );
      await tester.pump();

      // Type group name but leave display name blank
      final nameFields = find.byType(TextFormField);
      await tester.enterText(nameFields.first, 'My Group');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      // Unified validator: both fields share the same empty-name message.
      expect(find.text("Name can't be empty."), findsWidgets);

      // Reset for subsequent tests
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'Test User',
      });
    });

    testWidgets('renders close button in top bar', (tester) async {
      await tester.pumpWidget(await buildCreateScreen());
      await tester.pump();
      expect(find.byType(RIconButton), findsOneWidget);
    });

    testWidgets(
      'direct create close routes home when there is no stack to pop',
      (tester) async {
        await tester.pumpWidget(await buildCreateRoute());
        await tester.pumpAndSettle();

        await tester.tap(find.byType(RIconButton));
        await tester.pumpAndSettle();

        expect(find.text('Home'), findsOneWidget);
      },
    );

    testWidgets('renders form with TextFormFields', (tester) async {
      await tester.pumpWidget(await buildCreateScreen());
      await tester.pump();
      // Expect at least 2 text form fields: group name and display name
      expect(find.byType(TextFormField), findsAtLeastNWidgets(2));
    });

    testWidgets('group name text field accepts input', (tester) async {
      await tester.pumpWidget(await buildCreateScreen());
      await tester.pump();

      final nameFields = find.byType(TextFormField);
      await tester.enterText(nameFields.first, 'My Travel Group');
      expect(find.text('My Travel Group'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // JoinGroupScreen tests
  // ---------------------------------------------------------------------------

  group('JoinGroupScreen', () {
    setUpAll(() {
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'Test User',
      });
    });

    Future<Widget> buildJoinScreen({
      bool loading = false,
      Locale locale = const Locale('en'),
    }) async {
      final prefs = await SharedPreferences.getInstance();
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          groupLoadingProvider.overrideWith((ref) => loading),
          groupErrorProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const JoinGroupScreen(),
        ),
      );
    }

    Future<Widget> buildJoinInviteRoute() async {
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'Test User',
      });
      final prefs = await SharedPreferences.getInstance();
      final router = GoRouter(
        initialLocation: '/join/ABC123',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const Scaffold(body: Text('Home')),
          ),
          GoRoute(
            path: '/join/:code',
            builder: (context, state) => JoinGroupScreen(
              initialInviteCode: state.pathParameters['code'],
            ),
          ),
        ],
      );
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          groupLoadingProvider.overrideWith((ref) => false),
          groupErrorProvider.overrideWith((ref) => null),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      );
    }

    testWidgets('renders AppBar with Join a Group title', (tester) async {
      await tester.pumpWidget(await buildJoinScreen());
      await tester.pump();
      expect(find.text('Join a Group'), findsOneWidget);
    });

    testWidgets(
      'direct invite close routes home when there is no stack to pop',
      (tester) async {
        await tester.pumpWidget(await buildJoinInviteRoute());
        await tester.pumpAndSettle();

        await tester.tap(find.byType(RIconButton));
        await tester.pumpAndSettle();

        expect(find.text('Home'), findsOneWidget);
      },
    );

    testWidgets('renders Your name label', (tester) async {
      await tester.pumpWidget(await buildJoinScreen());
      await tester.pump();
      expect(find.text('Your name'), findsOneWidget);
    });

    // #293: the join name field no longer pre-fills from the device-wide name
    // (it bled a casual nickname into another group's ledger). The blank-field
    // behavior is pinned by '#293: name field is blank on a fresh join' below.

    testWidgets('renders Invite code label', (tester) async {
      await tester.pumpWidget(await buildJoinScreen());
      await tester.pump();
      expect(find.text('Invite code'), findsOneWidget);
    });

    testWidgets('renders Arabic labels and name validation error', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'settings_device_name': ''});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            groupLoadingProvider.overrideWith((ref) => false),
            groupErrorProvider.overrideWith((ref) => null),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            locale: const Locale('ar'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const JoinGroupScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('اسمك'), findsOneWidget);
      expect(find.text('رمز الدعوة'), findsOneWidget);

      // Valid-alphabet 6-char code (no I/O/0/1) so the first-completion
      // auto-submit fires; the blank name then surfaces the name-empty error.
      await tester.enterText(find.byType(TextFormField).last, 'ABCD23');
      await tester.pumpAndSettle();

      expect(find.text('لا يمكن أن يكون الاسم فارغًا.'), findsOneWidget);
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'Test User',
      });
    });

    testWidgets('renders 6-character instruction text', (tester) async {
      await tester.pumpWidget(await buildJoinScreen());
      await tester.pump();
      expect(
        find.text('Ask a group member for their 6-character code'),
        findsOneWidget,
      );
    });

    testWidgets('renders Join Group button', (tester) async {
      await tester.pumpWidget(await buildJoinScreen());
      await tester.pump();
      expect(find.text('Join Group'), findsOneWidget);
    });

    testWidgets('Join Group button is disabled when code field is empty', (
      tester,
    ) async {
      await tester.pumpWidget(await buildJoinScreen());
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Join Group'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('shows CircularProgressIndicator when loading is true', (
      tester,
    ) async {
      // LoadingButton shows CircularProgressIndicator when isLoading=true.
      await tester.pumpWidget(await buildJoinScreen(loading: true));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders ABC234 hint text in code input', (tester) async {
      await tester.pumpWidget(await buildJoinScreen());
      await tester.pump();
      // #293: the hint uses only invite-alphabet chars (no I/O/0/1).
      expect(find.text('ABC234'), findsOneWidget);
    });

    testWidgets('code input uppercases typed text', (tester) async {
      await tester.pumpWidget(await buildJoinScreen());
      await tester.pump();

      // The code field is the last TextFormField on the screen. '23' avoids the
      // now-excluded digit '1' (#293) and stays under 6 chars (no auto-submit).
      final codeField = find.byType(TextFormField).last;
      await tester.enterText(codeField, 'abc23');
      await tester.pump();

      expect(find.text('ABC23'), findsOneWidget);
    });

    testWidgets('rate-limited join shows the callable message', (tester) async {
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'Joiner',
      });
      final prefs = await SharedPreferences.getInstance();
      final fakeDb = FakeFirebaseFirestore();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            groupLoadingProvider.overrideWith((ref) => false),
            groupErrorProvider.overrideWith((ref) => null),
            groupServiceProvider.overrideWith(
              (ref) => GroupService.withFirestore(
                ref,
                fakeDb,
                currentUserId: 'uid-joiner',
                joinGroupCallableOverride:
                    ({required inviteCode, required displayName}) async {
                      throw FirebaseFunctionsException(
                        code: 'resource-exhausted',
                        message: 'Too many attempts. Try again later.',
                      );
                    },
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const JoinGroupScreen(),
          ),
        ),
      );
      await tester.pump();

      // #293: name no longer pre-fills, so type it; valid-alphabet code lets the
      // first-completion auto-submit fire and reach the (throwing) join callable.
      await tester.enterText(find.byType(TextFormField).first, 'Joiner');
      await tester.enterText(find.byType(TextFormField).last, 'ABCD23');
      await tester.pumpAndSettle();

      expect(find.text('Too many attempts. Try again later.'), findsOneWidget);
      expect(
        find.text(
          "Couldn't join the group. Check your connection and try again.",
        ),
        findsNothing,
      );
    });

    testWidgets('#279: name-collision join shows the localized name-taken message', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'Joiner',
      });
      final prefs = await SharedPreferences.getInstance();
      final fakeDb = FakeFirebaseFirestore();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            groupLoadingProvider.overrideWith((ref) => false),
            groupErrorProvider.overrideWith((ref) => null),
            groupServiceProvider.overrideWith(
              (ref) => GroupService.withFirestore(
                ref,
                fakeDb,
                currentUserId: 'uid-joiner',
                joinGroupCallableOverride:
                    ({required inviteCode, required displayName}) async {
                      // The #279 server guard throws this code on a collision.
                      throw FirebaseFunctionsException(
                        code: 'already-exists',
                        message:
                            'That name is already taken in this group. '
                            'Please choose a different name.',
                      );
                    },
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const JoinGroupScreen(),
          ),
        ),
      );
      await tester.pump();

      // #293: type the (no-longer-prefilled) name + a valid-alphabet code so the
      // first-completion auto-submit reaches the collision-throwing callable.
      await tester.enterText(find.byType(TextFormField).first, 'Joiner');
      await tester.enterText(find.byType(TextFormField).last, 'ABCD23');
      await tester.pumpAndSettle();

      expect(
        find.text(
          "That name's already used in this group. Please pick a different name.",
        ),
        findsOneWidget,
      );
      // NOT the generic failure copy.
      expect(
        find.text(
          "Couldn't join the group. Check your connection and try again.",
        ),
        findsNothing,
      );
    });

    testWidgets(
      '#633: successful join marks the group aggregate dirty before routing',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'settings_device_name': 'Joiner',
        });
        final prefs = await SharedPreferences.getInstance();
        final fakeDb = FakeFirebaseFirestore();
        await fakeDb.collection('groups').doc('g-joined').set({
          'name': 'Trip',
          'inviteCode': 'ABCD23',
          'createdBy': 'uid-owner',
          'memberIds': ['uid-owner', 'uid-joiner'],
          'currency': 'OMR',
          'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        });

        final router = GoRouter(
          initialLocation: '/join',
          routes: [
            GoRoute(
              path: '/join',
              builder: (context, state) =>
                  const JoinGroupScreen(initialInviteCode: 'ABCD23'),
            ),
            GoRoute(
              path: '/group/:gid',
              builder: (context, state) =>
                  const Scaffold(body: Text('group-landing')),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              notificationPromptProvider.overrideWithValue(_NoopPrompt()),
              groupLoadingProvider.overrideWith((ref) => false),
              groupErrorProvider.overrideWith((ref) => null),
              groupServiceProvider.overrideWith(
                (ref) => GroupService.withFirestore(
                  ref,
                  fakeDb,
                  currentUserId: 'uid-joiner',
                  joinGroupCallableOverride:
                      ({required inviteCode, required displayName}) async {
                        expect(inviteCode, 'ABCD23');
                        expect(displayName, 'Joiner');
                        return 'g-joined';
                      },
                ),
              ),
            ],
            child: MaterialApp.router(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            ),
          ),
        );
        await tester.pump();

        await tester.enterText(find.byType(TextFormField).first, 'Joiner');
        await tester.pump();
        // #1041: the top bar grew to the 44dp §4 floor, nudging the button
        // out of the default test viewport — ensureVisible before tapping.
        await tester.ensureVisible(find.byKey(GroupKeys.joinGroupButton));
        await tester.tap(find.byKey(GroupKeys.joinGroupButton));
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(MaterialApp)),
        );
        expect(find.text('group-landing'), findsOneWidget);
        expect(
          container.read(balanceAggregateFreshnessProvider),
          contains('g-joined'),
        );
      },
    );

    testWidgets(
      '#293: name field is blank on a fresh join (no device-name bleed)',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'settings_device_name': 'Booboo',
        });
        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              groupLoadingProvider.overrideWith((ref) => false),
              groupErrorProvider.overrideWith((ref) => null),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const JoinGroupScreen(),
            ),
          ),
        );
        await tester.pump();

        // The saved device name must NOT silently pre-load into the join name
        // field — it would carry the wrong persona into another group's ledger.
        expect(find.text('Booboo'), findsNothing);
        final nameField = tester.widget<TextFormField>(
          find.byType(TextFormField).first,
        );
        expect(nameField.controller!.text, isEmpty);
        SharedPreferences.setMockInitialValues({
          'settings_device_name': 'Test User',
        });
      },
    );

    testWidgets('#293: invite field rejects ambiguous chars I/O/0/1', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'settings_device_name': ''});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            groupLoadingProvider.overrideWith((ref) => false),
            groupErrorProvider.overrideWith((ref) => null),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const JoinGroupScreen(),
          ),
        ),
      );
      await tester.pump();

      final codeField = find.byType(TextFormField).last;
      // The invite alphabet excludes I, O, 0 and 1 (group_provider
      // _generateInviteCode). Typing them must be filtered so a glyph-confusion
      // mistype can never be entered — and so can never auto-submit a
      // guaranteed-invalid code that burns the 5/hr join lockout.
      await tester.enterText(codeField, 'ABO0I1');
      await tester.pump();
      expect(tester.widget<TextFormField>(codeField).controller!.text, 'AB');

      // Valid-alphabet chars still pass through and uppercase (5 chars: no
      // auto-submit).
      await tester.enterText(codeField, 'abcd2');
      await tester.pump();
      expect(tester.widget<TextFormField>(codeField).controller!.text, 'ABCD2');
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'Test User',
      });
    });

    testWidgets(
      '#293: auto-submit fires at most once; a corrected code needs a Join tap',
      (tester) async {
        SharedPreferences.setMockInitialValues({'settings_device_name': ''});
        final prefs = await SharedPreferences.getInstance();
        final fakeDb = FakeFirebaseFirestore();
        var joinCount = 0;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              groupLoadingProvider.overrideWith((ref) => false),
              groupErrorProvider.overrideWith((ref) => null),
              groupServiceProvider.overrideWith(
                (ref) => GroupService.withFirestore(
                  ref,
                  fakeDb,
                  currentUserId: 'uid-joiner',
                  joinGroupCallableOverride:
                      ({required inviteCode, required displayName}) async {
                        joinCount++;
                        throw FirebaseFunctionsException(
                          code: 'not-found',
                          message: 'Invalid invite code.',
                        );
                      },
                ),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const JoinGroupScreen(),
            ),
          ),
        );
        await tester.pump();

        // Name + a complete code → auto-submits exactly once.
        await tester.enterText(find.byType(TextFormField).first, 'Joiner');
        await tester.enterText(find.byType(TextFormField).last, 'ABCD23');
        await tester.pumpAndSettle();
        expect(joinCount, 1);

        // Correcting the code (a different complete value) must NOT
        // auto-resubmit and burn another 5/hr attempt — only a deliberate Join
        // tap may.
        await tester.enterText(find.byType(TextFormField).last, 'ABCD24');
        await tester.pumpAndSettle();
        expect(joinCount, 1);

        // The manual Join button still works. (Clear the floating error
        // snackbar from the failed auto-submit first — it overlaps the button.)
        ScaffoldMessenger.of(
          tester.element(find.byType(JoinGroupScreen)),
        ).clearSnackBars();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(GroupKeys.joinGroupButton));
        await tester.pumpAndSettle();
        expect(joinCount, 2);
        SharedPreferences.setMockInitialValues({
          'settings_device_name': 'Test User',
        });
      },
    );
  });

  // ---------------------------------------------------------------------------
  // JoinGroupScreen — #818 relocated from durable_gate_wiring_test.dart
  // ---------------------------------------------------------------------------
  //
  // These pinned that the JOIN path never required a #441 durable credential.
  // #818 removed the matching create requirement too, so there is no
  // create/join credential requirement left anywhere —
  // relocated here (not deleted) rather than lost, because the join-failure
  // test is the ONLY coverage of the groupJoinFailed snackbar.

  group('JoinGroupScreen — gate-removal pins (#818)', () {
    late _MockGroupService groupService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      groupService = _MockGroupService();
    });

    Widget wrapMocked(SharedPreferences sp) {
      final router = GoRouter(
        initialLocation: '/join',
        routes: [
          GoRoute(path: '/join', builder: (_, _) => const JoinGroupScreen()),
          GoRoute(
            path: '/group/:id',
            builder: (_, _) => const Scaffold(body: Text('group-landing')),
          ),
        ],
      );
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          groupServiceProvider.overrideWithValue(groupService),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      );
    }

    Future<void> typeJoin(WidgetTester tester) async {
      final fields = find.byType(TextField);
      // Name field (0), invite-code field (1).
      await tester.enterText(fields.at(0), 'Tester');
      await tester.pump();
      await tester.enterText(fields.at(1), 'ABCDEF'); // 6th char auto-submits
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'join proceeds straight to joinGroup — no gate to consult (#648, #818)',
      (tester) async {
        when(
          () => groupService.joinGroup(inviteCode: any(named: 'inviteCode')),
        ).thenAnswer((_) async => _gateRemovalGroup());

        final sp = await SharedPreferences.getInstance();
        await tester.pumpWidget(wrapMocked(sp));
        await tester.pumpAndSettle();

        await typeJoin(tester);

        verify(() => groupService.joinGroup(inviteCode: 'ABCDEF')).called(1);
        expect(find.text('group-landing'), findsOneWidget);
      },
    );

    testWidgets('a join failure surfaces the generic join error', (
      tester,
    ) async {
      when(
        () => groupService.joinGroup(inviteCode: any(named: 'inviteCode')),
      ).thenThrow(Exception('boom'));

      final sp = await SharedPreferences.getInstance();
      await tester.pumpWidget(wrapMocked(sp));
      await tester.pumpAndSettle();

      await typeJoin(tester);

      expect(find.text(AppLocalizationsEn().groupJoinFailed), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // GroupSettingsScreen tests
  // ---------------------------------------------------------------------------

  group('GroupSettingsScreen', () {
    setUpAll(() {
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'Test User',
      });
    });

    final testGroup = Group(
      id: 'group-1',
      name: 'Adventure Crew',
      inviteCode: 'XYZ789',
      createdBy: 'uid-creator',
      memberIds: const ['uid-creator'],
      currency: 'OMR',
      createdAt: DateTime(2026, 1, 1),
    );

    final testMembers = [
      GroupMember(
        id: 'mem-1',
        groupId: 'group-1',
        userId: 'uid-creator',
        displayName: 'Alice',
        role: 'CREATOR',
        joinedAt: DateTime(2026, 1, 1),
      ),
    ];

    Future<Widget> buildSettingsScreen() async {
      final prefs = await SharedPreferences.getInstance();
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue('uid-creator'),
          groupDetailProvider(
            'group-1',
          ).overrideWith((ref) => Stream.value(testGroup)),
          groupMembersProvider(
            'group-1',
          ).overrideWith((ref) => Stream.value(testMembers)),
          groupBalancesProvider('group-1').overrideWith(
            (ref) => const AsyncValue.data((
              balances: <String, List<UserBalance>>{},
              totalSpent: <String, Decimal>{},
              eventCount: 0,
              perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
              memberNames: <String, String>{},
              memberRawNames: <String, String>{},
            )),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const GroupSettingsScreen(groupId: 'group-1'),
        ),
      );
    }

    testWidgets('renders back button (no AppBar)', (tester) async {
      await tester.pumpWidget(await buildSettingsScreen());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('group_settings_back_button')),
        findsOneWidget,
      );
    });

    testWidgets('renders group created subtitle', (tester) async {
      await tester.pumpWidget(await buildSettingsScreen());
      await tester.pumpAndSettle();
      expect(find.textContaining('Created '), findsOneWidget);
    });

    testWidgets('renders group name value', (tester) async {
      await tester.pumpWidget(await buildSettingsScreen());
      await tester.pumpAndSettle();
      expect(find.text('Adventure Crew'), findsOneWidget);
    });

    testWidgets('renders invite-code helper text', (tester) async {
      await tester.pumpWidget(await buildSettingsScreen());
      await tester.pumpAndSettle();
      expect(find.text('Anyone with the code can join'), findsOneWidget);
    });

    testWidgets('renders invite code value', (tester) async {
      await tester.pumpWidget(await buildSettingsScreen());
      await tester.pumpAndSettle();
      expect(find.text('XYZ789'), findsOneWidget);
    });

    testWidgets('shows skeleton loader when group stream not yet emitted', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      final widget = ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue('uid-creator'),
          groupDetailProvider(
            'group-loading',
          ).overrideWith((ref) => const Stream.empty()),
          groupMembersProvider(
            'group-loading',
          ).overrideWith((ref) => const Stream.empty()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const GroupSettingsScreen(groupId: 'group-loading'),
        ),
      );
      await tester.pumpWidget(widget);
      await tester.pump();
      expect(find.byType(SkeletonLoader), findsOneWidget);
    });

    testWidgets('shows error text when group stream errors', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final widget = ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue('uid-creator'),
          groupDetailProvider('group-error').overrideWith(
            (ref) => Stream<Group?>.error(Exception('test error')),
          ),
          groupMembersProvider(
            'group-error',
          ).overrideWith((ref) => const Stream.empty()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const GroupSettingsScreen(groupId: 'group-error'),
        ),
      );
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();
      expect(find.text('Could not load settings'), findsOneWidget);
    });
  });
}
