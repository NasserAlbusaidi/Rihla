// Screen-side consumption of a PendingGateIntent (#428 PR-A1).
//
// A marker persisted before the gate-conflict discard-shell restart is
// consumed ONE-SHOT by the matching screen's prefill: controllers filled,
// marker cleared. A wrong-screen read leaves the marker untouched so the
// right screen can still consume it. Harness mirrors
// durable_gate_wiring_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/services/pending_gate_intent.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/screens/create_group_screen.dart';
import 'package:safar/features/groups/screens/join_group_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget wrap(SharedPreferences sp, Widget home) {
    final router = GoRouter(
      initialLocation: '/screen',
      routes: [GoRoute(path: '/screen', builder: (_, _) => home)],
    );
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        deviceLocalesProvider.overrideWithValue(const [Locale('en')]),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
  }

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  String fieldText(WidgetTester tester, Finder finder) =>
      tester.widget<TextField>(finder).controller!.text;

  // GroupKeys.* sit on wrapper widgets — read the descendant TextField.
  String keyedFieldText(WidgetTester tester, Key key) => fieldText(
        tester,
        find.descendant(of: find.byKey(key), matching: find.byType(TextField)),
      );

  group('JoinGroupScreen prefill', () {
    testWidgets('join marker prefills code + name and clears one-shot',
        (tester) async {
      final sp = await prefs();
      await PendingGateIntent.save(
        sp,
        PendingGateIntent.join(joinCode: 'ABC123', displayName: 'Nasser'),
      );

      await tester.pumpWidget(wrap(sp, const JoinGroupScreen()));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      // Name field (0), invite-code field (1) — order pinned by
      // durable_gate_wiring_test.dart.
      expect(fieldText(tester, fields.at(0)), 'Nasser');
      expect(fieldText(tester, fields.at(1)), 'ABC123');
      expect(PendingGateIntent.read(sp), isNull);
    });

    testWidgets('route-supplied initialInviteCode wins over the marker code',
        (tester) async {
      final sp = await prefs();
      await PendingGateIntent.save(
        sp,
        PendingGateIntent.join(joinCode: 'MARKER', displayName: 'Nasser'),
      );

      await tester.pumpWidget(
        wrap(sp, const JoinGroupScreen(initialInviteCode: 'ROUTED')),
      );
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      expect(fieldText(tester, fields.at(1)), 'ROUTED');
      // Display name still comes from the marker.
      expect(fieldText(tester, fields.at(0)), 'Nasser');
      expect(PendingGateIntent.read(sp), isNull);
    });

    testWidgets('create marker does NOT prefill join and stays persisted',
        (tester) async {
      final sp = await prefs();
      await PendingGateIntent.save(
        sp,
        PendingGateIntent.create(
          groupName: 'Muscat Trip',
          displayName: 'Nasser',
          currencyCode: 'USD',
        ),
      );

      await tester.pumpWidget(wrap(sp, const JoinGroupScreen()));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      expect(fieldText(tester, fields.at(1)), isEmpty);
      expect(PendingGateIntent.read(sp), isNotNull);
    });

    testWidgets('no marker → unchanged behavior (name seeded from settings)',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'DeviceName',
      });
      final sp = await prefs();

      await tester.pumpWidget(wrap(sp, const JoinGroupScreen()));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      expect(fieldText(tester, fields.at(0)), 'DeviceName');
      expect(fieldText(tester, fields.at(1)), isEmpty);
    });

    testWidgets('marker displayName wins over the settings seed',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'DeviceName',
      });
      final sp = await prefs();
      await PendingGateIntent.save(
        sp,
        PendingGateIntent.join(joinCode: 'ABC123', displayName: 'Typed'),
      );

      await tester.pumpWidget(wrap(sp, const JoinGroupScreen()));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      expect(fieldText(tester, fields.at(0)), 'Typed');
    });
  });

  group('CreateGroupScreen prefill', () {
    testWidgets('create marker prefills name/displayName/currency and clears',
        (tester) async {
      final sp = await prefs();
      await PendingGateIntent.save(
        sp,
        PendingGateIntent.create(
          groupName: 'Muscat Trip',
          displayName: 'Nasser',
          currencyCode: 'USD',
        ),
      );

      await tester.pumpWidget(wrap(sp, const CreateGroupScreen()));
      await tester.pumpAndSettle();

      expect(keyedFieldText(tester, GroupKeys.groupNameInput), 'Muscat Trip');
      expect(keyedFieldText(tester, GroupKeys.deviceNameInput), 'Nasser');
      expect(find.text('USD'), findsOneWidget);
      expect(PendingGateIntent.read(sp), isNull);
    });

    testWidgets('invalid currency code falls back to the OMR default',
        (tester) async {
      final sp = await prefs();
      await PendingGateIntent.save(
        sp,
        PendingGateIntent.create(
          groupName: 'Muscat Trip',
          displayName: 'Nasser',
          currencyCode: 'XXX',
        ),
      );

      await tester.pumpWidget(wrap(sp, const CreateGroupScreen()));
      await tester.pumpAndSettle();

      expect(find.text('OMR'), findsOneWidget);
      expect(find.text('XXX'), findsNothing);
    });

    testWidgets('join marker does NOT prefill create and stays persisted',
        (tester) async {
      final sp = await prefs();
      await PendingGateIntent.save(
        sp,
        PendingGateIntent.join(joinCode: 'ABC123', displayName: 'Nasser'),
      );

      await tester.pumpWidget(wrap(sp, const CreateGroupScreen()));
      await tester.pumpAndSettle();

      expect(keyedFieldText(tester, GroupKeys.groupNameInput), isEmpty);
      expect(PendingGateIntent.read(sp), isNotNull);
    });
  });
}
