import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #945 — guard: the iOS Google Sign-In wiring must stay intact.
///
/// The Dart flow (`google_sign_in_gateway.dart`) passes only `serverClientId`,
/// so the native layer resolves the iOS OAuth client from the BUNDLED
/// `GoogleService-Info.plist` (`FLTGoogleSignInPlugin.m` falls back to its
/// `CLIENT_ID`), and the redirect returns via the `REVERSED_CLIENT_ID` custom
/// URL scheme in `Info.plist`. Losing either half silently kills Google
/// restore/linking (#441) on iOS — the exact dead state #945 fixed.
///
/// `GoogleService-Info.plist` itself is gitignored (platform config), so the
/// consistency check against it runs only where the file exists (dev machines,
/// release builds) and is skipped in CI.
void main() {
  const reversedClientId =
      'com.googleusercontent.apps.231518921973-husmvvkmm17gff534bo5r6j2ht9hat9m';

  test('Info.plist carries the Google Sign-In reversed-client-id scheme', () {
    final plist = File('ios/Runner/Info.plist');

    expect(plist.existsSync(), isTrue);
    expect(
      plist.readAsStringSync(),
      contains('<string>$reversedClientId</string>'),
      reason:
          'ios/Runner/Info.plist must keep the REVERSED_CLIENT_ID '
          'CFBundleURLSchemes entry — without it the GoogleSignIn SDK cannot '
          'complete the native redirect and restoreWithGoogle dead-ends (#945).',
    );
  });

  test('GoogleService-Info.plist is bundled into the Runner target', () {
    final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj');

    expect(pbxproj.existsSync(), isTrue);
    final content = pbxproj.readAsStringSync();
    expect(
      content,
      contains('GoogleService-Info.plist in Resources'),
      reason:
          'The google_sign_in_ios plugin resolves CLIENT_ID from the BUNDLED '
          'GoogleService-Info.plist (Dart passes only serverClientId). '
          'Removing it from the Resources build phase kills Google sign-in '
          'on iOS with no compile error (#945).',
    );
  });

  test(
    'local GoogleService-Info.plist is consistent with the Info.plist scheme',
    () {
      final googleServiceInfo = File('ios/Runner/GoogleService-Info.plist');
      if (!googleServiceInfo.existsSync()) {
        // Gitignored platform config — absent in CI; the consistency check
        // only runs where a local copy exists.
        return;
      }

      final content = googleServiceInfo.readAsStringSync();
      expect(
        content,
        contains('<string>$reversedClientId</string>'),
        reason:
            'GoogleService-Info.plist REVERSED_CLIENT_ID must match the '
            'CFBundleURLSchemes entry in Info.plist — a re-downloaded plist '
            'with a different OAuth client needs the Info.plist scheme '
            'updated in the same change (#945).',
      );
      expect(
        content,
        contains('<key>CLIENT_ID</key>'),
        reason:
            'A GoogleService-Info.plist without CLIENT_ID predates the iOS '
            'OAuth client — re-download it from the Firebase console (#945).',
      );
    },
  );
}
