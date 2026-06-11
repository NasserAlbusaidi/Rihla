// Unit tests for DurableCredentialGate (#441 PR2) — the screen-side
// chokepoint that decides whether create/join may proceed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/notification_service.dart';
import 'package:safar/features/auth/providers/durable_credential_gate_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockNotificationService extends Mock implements NotificationService {}

void main() {
  late _MockNotificationService notifications;

  setUp(() {
    notifications = _MockNotificationService();
    when(() => notifications.initialize()).thenAnswer((_) async => true);
  });

  Future<({DurableCredentialGate gate, BuildContext context})> build(
    WidgetTester tester, {
    required bool isAnonymous,
    required bool pushEnabled,
    required DurableCredentialSheetPresenter presentSheet,
    bool sheetCalls = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      'settings_push_notifications': pushEnabled,
    });
    final prefs = await SharedPreferences.getInstance();
    late DurableCredentialGate gate;
    final gateProvider = Provider<DurableCredentialGate>(
      (ref) => DurableCredentialGate(
        ref,
        isAnonymous: () => isAnonymous,
        presentSheet: presentSheet,
      ),
    );
    late BuildContext capturedContext;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          notificationServiceProvider.overrideWithValue(notifications),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              capturedContext = context;
              gate = ref.read(gateProvider);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return (gate: gate, context: capturedContext);
  }

  testWidgets('non-anonymous user passes without presenting the sheet', (
    tester,
  ) async {
    var presented = false;
    final h = await build(
      tester,
      isAnonymous: false,
      pushEnabled: false,
      presentSheet: (_, {intent}) async {
        presented = true;
        return true;
      },
    );

    expect(await h.gate.ensure(h.context), isTrue);
    expect(presented, isFalse);
  });

  testWidgets('anonymous user + declined sheet blocks the action', (
    tester,
  ) async {
    final h = await build(
      tester,
      isAnonymous: true,
      pushEnabled: true,
      presentSheet: (_, {intent}) async => false,
    );

    expect(await h.gate.ensure(h.context), isFalse);
    verifyNever(() => notifications.initialize());
  });

  testWidgets(
    'anonymous user + linked sheet proceeds and re-saves the FCM token '
    'when push is enabled',
    (tester) async {
      final h = await build(
        tester,
        isAnonymous: true,
        pushEnabled: true,
        presentSheet: (_, {intent}) async => true,
      );

      expect(await h.gate.ensure(h.context), isTrue);
      await tester.pump();
      verify(() => notifications.initialize()).called(1);
    },
  );

  testWidgets('linked sheet does NOT touch notifications when push is off', (
    tester,
  ) async {
    final h = await build(
      tester,
      isAnonymous: true,
      pushEnabled: false,
      presentSheet: (_, {intent}) async => true,
    );

    expect(await h.gate.ensure(h.context), isTrue);
    await tester.pump();
    verifyNever(() => notifications.initialize());
  });
}
