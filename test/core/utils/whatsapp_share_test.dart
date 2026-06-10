import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:safar/core/config/app_links.dart';
import 'package:safar/core/utils/whatsapp_share.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _MockUrlLauncher extends Mock
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => registerFallbackValue(const LaunchOptions()));

  group('whatsAppInviteUri', () {
    test('builds a whatsapp://send deep link carrying the message as text', () {
      const message = 'hello there';
      final uri = whatsAppInviteUri(message);

      expect(uri.scheme, 'whatsapp');
      expect(uri.host, 'send');
      expect(uri.queryParameters['text'], message);
    });

    test('faithfully carries the web.app/join invite URL, never rihla.app', () {
      final inviteUrl = AppLinks.inviteUrl('AB12CD').toString();
      final message = "Join 'Trip' on Rihla: $inviteUrl or use code AB12CD.";

      final uri = whatsAppInviteUri(message);

      // The decoded text param round-trips the invite message verbatim.
      expect(uri.queryParameters['text'], message);
      expect(uri.queryParameters['text'], contains('rihla-safar.web.app/join/AB12CD'));
      // And the parked/dead host never leaks in (#130/#354).
      expect(uri.toString(), isNot(contains('rihla.app/')));
      expect(uri.queryParameters['text'], isNot(contains('rihla.app/')));
    });
  });

  group('shareInviteViaWhatsApp', () {
    late _MockUrlLauncher launcher;

    setUp(() {
      launcher = _MockUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
    });

    test('launches WhatsApp and skips the fallback when installed', () async {
      when(() => launcher.canLaunch(any())).thenAnswer((_) async => true);
      when(() => launcher.launchUrl(any(), any())).thenAnswer((_) async => true);
      var fallbackCalls = 0;

      await shareInviteViaWhatsApp(
        'msg',
        fallback: () async => fallbackCalls++,
      );

      final captured =
          verify(() => launcher.launchUrl(captureAny(), any())).captured.single;
      expect(captured, startsWith('whatsapp://send?text='));
      expect(fallbackCalls, 0);
    });

    test('falls back to the OS share sheet when WhatsApp is not installed',
        () async {
      when(() => launcher.canLaunch(any())).thenAnswer((_) async => false);
      var fallbackCalls = 0;

      await shareInviteViaWhatsApp(
        'msg',
        fallback: () async => fallbackCalls++,
      );

      verifyNever(() => launcher.launchUrl(any(), any()));
      expect(fallbackCalls, 1);
    });

    test('falls back when the launch throws', () async {
      when(() => launcher.canLaunch(any())).thenAnswer((_) async => true);
      when(() => launcher.launchUrl(any(), any())).thenThrow(Exception('boom'));
      var fallbackCalls = 0;

      await shareInviteViaWhatsApp(
        'msg',
        fallback: () async => fallbackCalls++,
      );

      expect(fallbackCalls, 1);
    });

    test('falls back when launch reports failure', () async {
      when(() => launcher.canLaunch(any())).thenAnswer((_) async => true);
      when(() => launcher.launchUrl(any(), any())).thenAnswer((_) async => false);
      var fallbackCalls = 0;

      await shareInviteViaWhatsApp(
        'msg',
        fallback: () async => fallbackCalls++,
      );

      expect(fallbackCalls, 1);
    });
  });
}
