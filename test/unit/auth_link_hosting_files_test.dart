import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Firebase Hosting serves the account recovery continue page', () {
    final firebaseJson =
        jsonDecode(File('firebase.json').readAsStringSync())
            as Map<String, Object?>;
    final hosting = firebaseJson['hosting'] as Map<String, Object?>;

    expect(hosting['public'], 'hosting');
    expect(
      hosting['headers'].toString(),
      contains('/.well-known/apple-app-site-association'),
    );
    expect(
      File('hosting/__/auth/links/continue.html').readAsStringSync(),
      contains('Rihla'),
    );
  });

  test('account recovery continue page falls back to the app scheme', () {
    final page = File('hosting/__/auth/links/continue.html').readAsStringSync();

    expect(page, contains('rihla://auth-link'));
    expect(page, contains('encodeURIComponent(window.location.href)'));
  });

  test('Digital Asset Links file matches the Android package', () {
    final statements =
        jsonDecode(
              File('hosting/.well-known/assetlinks.json').readAsStringSync(),
            )
            as List<Object?>;
    final statement = statements.single as Map<String, Object?>;
    final target = statement['target'] as Map<String, Object?>;

    expect(
      statement['relation'],
      contains('delegate_permission/common.handle_all_urls'),
    );
    expect(target['namespace'], 'android_app');
    expect(target['package_name'], 'com.safar.safar');
    expect(
      target['sha256_cert_fingerprints'].toString(),
      contains(
        '1D:15:D4:A5:CB:48:2E:B7:25:BC:EC:1E:51:B6:B4:EE:82:EC:DC:62:E1:E7:2A:96:CE:5D:D7:B7:A3:46:DD:F9',
      ),
    );
    expect(
      target['sha256_cert_fingerprints'].toString(),
      contains(
        '9B:DD:8C:4B:25:27:EB:D7:05:59:5E:15:90:E6:E3:5B:AE:E0:58:B9:FC:6D:7D:3D:7E:86:B1:93:08:2D:C4:47',
      ),
    );
  });

  test('Apple App Site Association file matches the iOS bundle id', () {
    final association =
        jsonDecode(
              File(
                'hosting/.well-known/apple-app-site-association',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final applinks = association['applinks'] as Map<String, Object?>;
    final details = applinks['details'] as List<Object?>;
    final firstApp = details.single as Map<String, Object?>;

    expect(firstApp['appIDs'], contains('GC6NXQSRUU.com.safar.safar'));
    expect(firstApp['components'].toString(), contains('/__/auth/links/*'));
    expect(firstApp['components'].toString(), contains('/join/*'));
    expect(firstApp['components'].toString(), contains('/join'));
  });

  test('Android manifest declares verified App Links for auth and invites', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:autoVerify="true"'));
    expect(manifest, contains('android:host="rihla-safar.firebaseapp.com"'));
    expect(manifest, contains('android:pathPrefix="/__/auth/links"'));
    expect(manifest, contains('android:host="rihla-safar.web.app"'));
    expect(manifest, contains('android:pathPrefix="/join"'));
  });

  test('iOS entitlements declare Universal Links for auth and invites', () {
    final entitlements = File(
      'ios/Runner/Runner.entitlements',
    ).readAsStringSync();

    expect(entitlements, contains('com.apple.developer.associated-domains'));
    expect(entitlements, contains('applinks:rihla-safar.firebaseapp.com'));
    expect(entitlements, contains('applinks:rihla-safar.web.app'));
  });

  test('Firebase Hosting rewrites invite links to a browser fallback', () {
    final firebaseJson =
        jsonDecode(File('firebase.json').readAsStringSync())
            as Map<String, Object?>;
    final hosting = firebaseJson['hosting'] as Map<String, Object?>;

    expect(hosting['rewrites'].toString(), contains('/join'));
    expect(hosting['rewrites'].toString(), contains('/join/**'));
    expect(
      File('hosting/join.html').readAsStringSync(),
      contains('rihla://join'),
    );
  });

  test('production-state check verifies both Firebase Hosting domains', () {
    final script = File('tool/check_firebase_prod_state.sh').readAsStringSync();

    expect(script, contains(r'check_hosting_domain "$hosting_web_base"'));
    expect(
      script,
      contains(r'check_hosting_domain "$hosting_firebaseapp_base"'),
    );
    expect(script, contains('/join/ABC123'));
    expect(script, contains('/.well-known/apple-app-site-association'));
    expect(script, contains('/.well-known/assetlinks.json'));
    expect(script, contains('/__/auth/links/continue'));
    expect(script, contains('rihla://auth-link'));
  });

  test('public Hosting copy matches opt-in email recovery behavior', () {
    final publicPages = [
      'hosting/index.html',
      'hosting/help.html',
      'hosting/privacy.html',
      'hosting/delete-data.html',
      'hosting/terms.html',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    expect(publicPages, contains('link an email'));
    expect(publicPages, contains('recovery email'));
    expect(
      publicPages,
      isNot(contains('Account recovery via email link is on the roadmap')),
    );
    expect(publicPages, isNot(contains('No account, no email')));
    expect(publicPages, isNot(contains('We cannot recover lost sessions')));
  });
}
