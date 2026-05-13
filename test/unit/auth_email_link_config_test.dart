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

    test(
      'leaves linkDomain unset so Firebase auto-selects the project default '
      '(passing *.web.app or *.firebaseapp.com here is rejected as '
      'auth/invalid-hosting-link-domain)',
      () {
        final settings = AuthEmailLinkConfig.actionCodeSettings();

        expect(settings.linkDomain, isNull);
      },
    );

    test(
      'pins the Hosting domain to the project firebaseapp.com alias — the '
      'auto-selected Firebase Auth continue-URL host',
      () {
        expect(AuthEmailLinkConfig.hostingDomain, 'rihla-safar.firebaseapp.com');
      },
    );

    test('keeps the Firebase Hosting continue URL stable', () {
      expect(
        AuthEmailLinkConfig.continueUrl,
        'https://rihla-safar.firebaseapp.com/__/auth/links/continue',
      );
    });

    test(
      'classifies Firebase email auth links without accepting random links',
      () {
        const emailLink =
            'https://rihla-safar.firebaseapp.com/__/auth/links/continue?mode=signIn&oobCode=abc123&apiKey=fake';

        expect(AuthEmailLinkConfig.looksLikeEmailAuthLink(emailLink), isTrue);
        expect(
          AuthEmailLinkConfig.looksLikeEmailAuthLink(
            'https://rihla-safar.firebaseapp.com/profile',
          ),
          isFalse,
        );
      },
    );

    group('redactForLogging', () {
      test('replaces oobCode and apiKey with REDACTED', () {
        const link =
            'https://rihla-safar.firebaseapp.com/__/auth/links/continue?mode=signIn&oobCode=secret123&apiKey=AIza-fake&lang=en';

        final redacted = AuthEmailLinkConfig.redactForLogging(link);

        expect(redacted, contains('mode=signIn'));
        expect(redacted, contains('lang=en'));
        expect(redacted, contains('oobCode=REDACTED'));
        expect(redacted, contains('apiKey=REDACTED'));
        expect(redacted, isNot(contains('secret123')));
        expect(redacted, isNot(contains('AIza-fake')));
      });

      test('returns sentinel for malformed URLs', () {
        expect(
          AuthEmailLinkConfig.redactForLogging('::not a url::'),
          '<unparseable-link>',
        );
      });

      test('passes through URLs that carry no credential params unchanged', () {
        const link = 'https://rihla-safar.firebaseapp.com/profile';
        expect(AuthEmailLinkConfig.redactForLogging(link), link);
      });
    });
  });
}
