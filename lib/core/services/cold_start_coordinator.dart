import 'deep_link_service.dart';

/// Runs the ordered cold-start side-effects, isolating each step so that a
/// failure in deep-link resolution or install-referrer consumption can never
/// suppress account-recovery activation (`activateAppBootstrap` wires the
/// recovery email-link listener + FCM registration) or the initial notification
/// sync for that launch (#724 moved bootstrap into this chain; an unguarded
/// throw in an early step would otherwise inert recovery + notifs).
///
/// A dropped decision fails open: deep-link resolution falling over yields a
/// neutral decision (referrer not suppressed, no join routed) so the deferred
/// invite still gets its chance and the downstream steps run normally. Swallowed
/// errors are surfaced via [onStepError] rather than silently eaten.
Future<void> runColdStartCoordinator({
  required Future<DeepLinkInitialDecision> Function() resolveDeepLinks,
  required Future<bool> Function({required bool route}) consumeInstallReferrer,
  required Future<void> Function() activateAppBootstrap,
  required Future<void> Function({required bool handleInitialMessage})
  runInitialNotificationSync,
  void Function(Object error, StackTrace stack)? onStepError,
}) async {
  Future<T> guarded<T>(Future<T> Function() run, T fallback) async {
    try {
      return await run();
    } catch (error, stack) {
      onStepError?.call(error, stack);
      return fallback;
    }
  }

  final deepLinkDecision = await guarded(
    resolveDeepLinks,
    const DeepLinkInitialDecision(
      joinRouted: false,
      suppressInstallReferrer: false,
    ),
  );
  final installReferrerRouted = await guarded(
    () => consumeInstallReferrer(
      route: !deepLinkDecision.suppressInstallReferrer,
    ),
    false,
  );
  final joinAlreadyRouted =
      deepLinkDecision.joinRouted || installReferrerRouted;

  await guarded(activateAppBootstrap, null);
  await guarded(
    () => runInitialNotificationSync(handleInitialMessage: !joinAlreadyRouted),
    null,
  );
}
