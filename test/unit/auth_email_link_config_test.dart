import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/auth/services/auth_email_link_config.dart';

void main() {
  group('AuthEmailLinkConfig', () {
    test('builds email link action settings for in-app handling', () {
      final settings = AuthEmailLinkConfig.actionCodeSettings();

      expect(settings.url, AuthEmailLinkConfig.continueUrl);
      expect(settings.handleCodeInApp, isTrue);
      expect(settings.androidPackageName, 'com.safar.safar');
      expect(settings.androidInstallApp, isTrue);
      expect(settings.iOSBundleId, 'com.safar.safar');
    });

    test('keeps the Firebase Hosting continue URL stable', () {
      expect(
        AuthEmailLinkConfig.continueUrl,
        'https://rihla-safar.web.app/__/auth/links/continue',
      );
    });

    test(
      'classifies Firebase email auth links without accepting random links',
      () {
        const emailLink =
            'https://rihla-safar.web.app/__/auth/links/continue?mode=signIn&oobCode=abc123&apiKey=fake';

        expect(AuthEmailLinkConfig.looksLikeEmailAuthLink(emailLink), isTrue);
        expect(
          AuthEmailLinkConfig.looksLikeEmailAuthLink(
            'https://rihla-safar.web.app/profile',
          ),
          isFalse,
        );
      },
    );
  });
}
