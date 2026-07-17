import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';

import '../providers/settings_provider.dart';

/// Seam for tests — the plugin singleton talks to a platform channel.
final inAppReviewProvider = Provider<InAppReview>((_) => InAppReview.instance);

/// Coordinates the contextual store-review ask (#1263).
final reviewPromptProvider = Provider<ReviewPrompt>(ReviewPrompt.new);

/// Asks for a store review at a natural moment — a settle-up completing —
/// via the platform in-app review flow (Play In-App Review /
/// SKStoreReviewController). Mirrors [NotificationPrompt]'s shape: one
/// fire-and-forget entry point, all gating internal, safe to call from any
/// UI success handler.
///
/// Gating, in order: emulator/QA builds never prompt; at most one attempt
/// per [cooldown] (Play's quota is ~1 successful prompt per device per 1–2
/// weeks and silently no-ops beyond it; iOS grants ≤3/year — the client
/// cooldown keeps attempts inside both budgets); the platform must report
/// the flow available (absent Play Services → skip, timestamp not burned).
/// Every failure path is swallowed — a review ask must never surface an
/// error into the settle flow that triggered it.
class ReviewPrompt {
  ReviewPrompt(this._ref, {DateTime Function()? now, bool? emulatorRun})
    : _now = now ?? DateTime.now,
      _emulatorRun =
          emulatorRun ??
          const bool.fromEnvironment(
            'USE_FIREBASE_EMULATOR',
            defaultValue: false,
          );

  static const String lastAttemptPrefsKey = 'reviewPromptLastAttemptMs';
  static const Duration cooldown = Duration(days: 14);

  final Ref _ref;
  final DateTime Function() _now;
  final bool _emulatorRun;
  bool _inFlight = false;

  /// Fire-and-forget: requests the in-app review flow if every gate passes.
  Future<void> maybeRequest() async {
    if (_inFlight || _emulatorRun) return;
    _inFlight = true;
    try {
      final prefs = _ref.read(sharedPreferencesProvider);
      final lastMs = prefs.getInt(lastAttemptPrefsKey);
      final now = _now();
      if (lastMs != null &&
          now.difference(DateTime.fromMillisecondsSinceEpoch(lastMs)) <
              cooldown) {
        return;
      }
      final review = _ref.read(inAppReviewProvider);
      if (!await review.isAvailable()) return;
      // Persist BEFORE requesting: the OS shows UI next, and a kill mid-flow
      // must not re-arm an immediate retry on next launch.
      await prefs.setInt(lastAttemptPrefsKey, now.millisecondsSinceEpoch);
      await review.requestReview();
    } catch (_) {
      // Fail-open on purpose: unoverridden prefs in tests, MissingPlugin in
      // widget tests, or any platform hiccup — never let the ask leak an
      // error into the settle flow that triggered it.
    } finally {
      _inFlight = false;
    }
  }
}
