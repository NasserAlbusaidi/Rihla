// Unit tests for NotificationPrompt — the "request push permission at a natural
// moment" coordinator (#288). Verifies it prompts exactly once, persists the
// outcome, and never re-prompts.

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/notification_prompt.dart';
import 'package:safar/core/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockNotificationService extends Mock implements NotificationService {}

void main() {
  late MockNotificationService notifications;

  setUp(() {
    notifications = MockNotificationService();
    when(() => notifications.initialize()).thenAnswer((_) async => true);
    when(() => notifications.removeToken()).thenAnswer((_) async {});
  });

  Future<ProviderContainer> makeContainer({
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final instance = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(instance),
        deviceLocalesProvider.overrideWithValue(const [Locale('en')]),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('NotificationPrompt.maybePrompt', () {
    test('unseen + disabled + granted → initializes, enables push, marks seen',
        () async {
      when(() => notifications.initialize()).thenAnswer((_) async => true);
      final container = await makeContainer();

      await container.read(notificationPromptProvider).maybePrompt();

      verify(() => notifications.initialize()).called(1);
      final settings = container.read(settingsProvider);
      expect(settings.pushNotificationsEnabled, isTrue);
      expect(settings.notificationPromptSeen, isTrue);
    });

    test('unseen + disabled + denied → initializes, push stays off, marks seen',
        () async {
      when(() => notifications.initialize()).thenAnswer((_) async => false);
      final container = await makeContainer();

      await container.read(notificationPromptProvider).maybePrompt();

      verify(() => notifications.initialize()).called(1);
      final settings = container.read(settingsProvider);
      expect(settings.pushNotificationsEnabled, isFalse);
      expect(settings.notificationPromptSeen, isTrue);
    });

    test('already seen → never initializes, leaves settings untouched',
        () async {
      final container = await makeContainer(
        prefs: {'settings_notification_prompt_seen': true},
      );

      await container.read(notificationPromptProvider).maybePrompt();

      verifyNever(() => notifications.initialize());
      expect(
        container.read(settingsProvider).pushNotificationsEnabled,
        isFalse,
      );
    });

    test('push already enabled → never re-prompts, marks seen', () async {
      final container = await makeContainer(
        prefs: {'settings_push_notifications': true},
      );

      await container.read(notificationPromptProvider).maybePrompt();

      verifyNever(() => notifications.initialize());
      final settings = container.read(settingsProvider);
      expect(settings.pushNotificationsEnabled, isTrue);
      expect(settings.notificationPromptSeen, isTrue);
    });

    test('seen flag persists across a fresh container', () async {
      final container = await makeContainer();
      await container.read(notificationPromptProvider).maybePrompt();
      expect(container.read(settingsProvider).notificationPromptSeen, isTrue);

      // Re-load from the same SharedPreferences store.
      final reloaded = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          deviceLocalesProvider.overrideWithValue(const [Locale('en')]),
          notificationServiceProvider.overrideWithValue(notifications),
        ],
      );
      addTearDown(reloaded.dispose);
      expect(reloaded.read(settingsProvider).notificationPromptSeen, isTrue);
    });

    test('re-entrant double maybePrompt initializes at most once', () async {
      final container = await makeContainer();
      final prompt = container.read(notificationPromptProvider);

      await Future.wait([prompt.maybePrompt(), prompt.maybePrompt()]);

      verify(() => notifications.initialize()).called(1);
    });
  });
}
