import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/review_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockInAppReview extends Mock implements InAppReview {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockInAppReview review;

  setUp(() {
    review = _MockInAppReview();
    when(review.isAvailable).thenAnswer((_) async => true);
    when(review.requestReview).thenAnswer((_) async {});
  });

  Future<(ProviderContainer, SharedPreferences)> makeContainer({
    Map<String, Object> initialPrefs = const {},
    DateTime Function()? now,
    bool emulatorRun = false,
  }) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        inAppReviewProvider.overrideWithValue(review),
        reviewPromptProvider.overrideWith(
          (ref) => ReviewPrompt(ref, now: now, emulatorRun: emulatorRun),
        ),
      ],
    );
    addTearDown(container.dispose);
    return (container, prefs);
  }

  test('happy path: requests review and persists the attempt timestamp', () async {
    final now = DateTime.utc(2026, 7, 17, 12);
    final (container, prefs) = await makeContainer(now: () => now);

    await container.read(reviewPromptProvider).maybeRequest();

    verify(review.isAvailable).called(1);
    verify(review.requestReview).called(1);
    expect(
      prefs.getInt(ReviewPrompt.lastAttemptPrefsKey),
      now.millisecondsSinceEpoch,
    );
  });

  test('cooldown: a 13-day-old attempt suppresses the request', () async {
    final now = DateTime.utc(2026, 7, 17, 12);
    final last = now.subtract(const Duration(days: 13));
    final (container, _) = await makeContainer(
      initialPrefs: {
        ReviewPrompt.lastAttemptPrefsKey: last.millisecondsSinceEpoch,
      },
      now: () => now,
    );

    await container.read(reviewPromptProvider).maybeRequest();

    verifyNever(review.isAvailable);
    verifyNever(review.requestReview);
  });

  test('cooldown expiry: a 15-day-old attempt allows a new request', () async {
    final now = DateTime.utc(2026, 7, 17, 12);
    final last = now.subtract(const Duration(days: 15));
    final (container, prefs) = await makeContainer(
      initialPrefs: {
        ReviewPrompt.lastAttemptPrefsKey: last.millisecondsSinceEpoch,
      },
      now: () => now,
    );

    await container.read(reviewPromptProvider).maybeRequest();

    verify(review.requestReview).called(1);
    expect(
      prefs.getInt(ReviewPrompt.lastAttemptPrefsKey),
      now.millisecondsSinceEpoch,
    );
  });

  test('emulator/QA runs never prompt and never touch prefs', () async {
    final (container, prefs) = await makeContainer(emulatorRun: true);

    await container.read(reviewPromptProvider).maybeRequest();

    verifyNever(review.isAvailable);
    verifyNever(review.requestReview);
    expect(prefs.getInt(ReviewPrompt.lastAttemptPrefsKey), isNull);
  });

  test('unavailable platform: no request, no timestamp burned', () async {
    when(review.isAvailable).thenAnswer((_) async => false);
    final (container, prefs) = await makeContainer();

    await container.read(reviewPromptProvider).maybeRequest();

    verifyNever(review.requestReview);
    expect(prefs.getInt(ReviewPrompt.lastAttemptPrefsKey), isNull);
  });

  test('plugin throwing is swallowed (fail-silent in success handlers)', () async {
    when(review.isAvailable).thenThrow(Exception('MissingPlugin'));
    final (container, _) = await makeContainer();

    await expectLater(
      container.read(reviewPromptProvider).maybeRequest(),
      completes,
    );
  });

  test('unoverridden prefs (throwing provider) is swallowed', () async {
    final container = ProviderContainer(
      overrides: [
        inAppReviewProvider.overrideWithValue(review),
        reviewPromptProvider.overrideWith(
          (ref) => ReviewPrompt(ref, emulatorRun: false),
        ),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(reviewPromptProvider).maybeRequest(),
      completes,
    );
    verifyNever(review.requestReview);
  });

  test('re-entrancy: concurrent calls produce one request', () async {
    final (container, _) = await makeContainer();
    final prompt = container.read(reviewPromptProvider);

    await Future.wait([prompt.maybeRequest(), prompt.maybeRequest()]);

    verify(review.requestReview).called(1);
  });
}
