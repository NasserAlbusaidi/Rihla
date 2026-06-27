import 'deep_link_service.dart';

Future<void> runColdStartCoordinator({
  required Future<DeepLinkInitialDecision> Function() resolveDeepLinks,
  required Future<bool> Function({required bool route}) consumeInstallReferrer,
  required Future<void> Function({required bool skipNavigation})
  replayGateIntent,
  required Future<void> Function() activateAppBootstrap,
  required Future<void> Function({required bool handleInitialMessage})
  runInitialNotificationSync,
}) async {
  final deepLinkDecision = await resolveDeepLinks();
  final installReferrerRouted = await consumeInstallReferrer(
    route: !deepLinkDecision.suppressInstallReferrer,
  );
  final joinAlreadyRouted =
      deepLinkDecision.joinRouted || installReferrerRouted;

  await replayGateIntent(skipNavigation: joinAlreadyRouted);
  await activateAppBootstrap();
  await runInitialNotificationSync(handleInitialMessage: !joinAlreadyRouted);
}
