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

    expect(firstApp['appIDs'], contains('T2U886CPS5.com.nalbusaidi.rihla'));
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
    // #130: the dead rihla.app host must not reappear, and the four live
    // autoVerify App Links (auth firebaseapp, web.app /join, firebaseapp /join)
    // must survive intact — guard the count so deleting the web.app filter or
    // re-adding rihla.app both fail here, not just a string-fragment match.
    expect(manifest, isNot(contains('android:host="rihla.app"')));
    expect('android:autoVerify="true"'.allMatches(manifest).length, 3);
  });

  test('iOS entitlements declare Universal Links for auth and invites', () {
    final entitlements = File(
      'ios/Runner/Runner.entitlements',
    ).readAsStringSync();

    expect(entitlements, contains('com.apple.developer.associated-domains'));
    expect(entitlements, contains('applinks:rihla-safar.firebaseapp.com'));
    expect(entitlements, contains('applinks:rihla-safar.web.app'));
    // #130: the dead rihla.app associated-domain must not reappear.
    expect(entitlements, isNot(contains('applinks:rihla.app')));
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

  test('web join page offers a Google Play install link (#276)', () {
    final page = File('hosting/join.html').readAsStringSync();

    // Someone without the app installed must not dead-end on the rihla://
    // scheme — the page has to offer a way to actually get the app. The link
    // lives in the static HTML (not only JS-injected) so it renders even when
    // the invite code is missing/invalid and the page never fully dead-ends.
    expect(
      page,
      contains('play.google.com/store/apps/details?id=com.safar.safar'),
    );
  });

  test(
    'web join page carries invite code through Play Install Referrer (#368)',
    () {
      final page = File('hosting/join.html').readAsStringSync();

      expect(page, contains(r'encodeURIComponent(`code=${code}`)'));
      expect(
        page,
        contains('play.google.com/store/apps/details?id=com.safar.safar'),
      );
    },
  );

  test('Android app declares the Play Install Referrer bridge (#368)', () {
    final build = File('android/app/build.gradle.kts').readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/safar/safar/MainActivity.kt',
    ).readAsStringSync();
    final dart = File(
      'lib/core/services/install_referrer_service.dart',
    ).readAsStringSync();

    expect(build, contains('com.android.installreferrer:installreferrer:2.2'));
    for (final source in [activity, dart]) {
      expect(source, contains('com.safar.safar/install_referrer'));
      expect(source, contains('getInstallReferrer'));
    }
    expect(activity, contains('endConnection()'));
  });

  test('landing page routes typed invite codes to the join fallback', () {
    final page = File('hosting/index.html').readAsStringSync();

    expect(page, contains('id="inviteForm"'));
    expect(page, contains('id="code"'));
    expect(page, contains("window.location.assign('/join/' + code)"));
    expect(page, contains('pattern="[A-Za-z0-9]{6}"'));
  });

  test('landing pages expose English and Arabic SEO alternates', () {
    final english = File('hosting/index.html').readAsStringSync();
    final arabic = File('hosting/ar.html').readAsStringSync();

    expect(english, contains('hreflang="en"'));
    expect(english, contains('href="https://rihla-safar.web.app/ar"'));
    expect(arabic, contains('<html lang="ar" dir="rtl">'));
    expect(arabic, contains('hreflang="ar"'));
    expect(arabic, contains('قسّم الفواتير'));
    expect(arabic, contains('id="inviteForm"'));
    expect(arabic, contains("window.location.assign('/join/' + code)"));
  });

  test('/join is noindexed for crawlers — thin utility page (#743)', () {
    final join = File('hosting/join.html').readAsStringSync();
    final robots = File('hosting/robots.txt').readAsStringSync();

    expect(join, contains('name="robots" content="noindex"'));
    expect(robots, contains('Disallow: /join'));
  });

  test('public site exposes sitemap and robots files for crawlers', () {
    final sitemap = File('hosting/sitemap.xml').readAsStringSync();
    final robots = File('hosting/robots.txt').readAsStringSync();

    expect(sitemap, contains('<loc>https://rihla-safar.web.app/</loc>'));
    expect(sitemap, contains('<loc>https://rihla-safar.web.app/ar</loc>'));
    expect(
      sitemap,
      contains('<loc>https://rihla-safar.web.app/split-bills-oman</loc>'),
    );
    expect(
      sitemap,
      contains('<loc>https://rihla-safar.web.app/ar/split-bills-oman</loc>'),
    );
    expect(sitemap, contains('<loc>https://rihla-safar.web.app/privacy</loc>'));
    // public-launch: the alpha pages are retired and must not be advertised
    // to crawlers any more.
    expect(sitemap, isNot(contains('/alpha</loc>')));
    expect(robots, contains('User-agent: *'));
    expect(
      robots,
      contains('Sitemap: https://rihla-safar.web.app/sitemap.xml'),
    );
  });

  test('public site has Oman split-bills SEO pages', () {
    final english = File('hosting/split-bills-oman.html').readAsStringSync();
    final arabic = File('hosting/ar/split-bills-oman.html').readAsStringSync();

    expect(english, contains('Split Bills in Oman'));
    expect(english, contains('Splitwise alternative for Oman'));
    expect(
      english,
      contains('href="https://rihla-safar.web.app/ar/split-bills-oman"'),
    );
    expect(english, contains('"@type": "FAQPage"'));
    expect(arabic, contains('<html lang="ar" dir="rtl">'));
    expect(arabic, contains('تقسيم الفواتير في عمان'));
    expect(arabic, contains('بديل Splitwise في عمان'));
    expect(
      arabic,
      contains('href="https://rihla-safar.web.app/split-bills-oman"'),
    );
    expect(arabic, contains('"@type": "FAQPage"'));
  });

  test('retired Android alpha pages are noindex redirects to the live app', () {
    final english = File('hosting/alpha.html').readAsStringSync();
    final arabic = File('hosting/ar/alpha.html').readAsStringSync();
    final join = File('hosting/join.html').readAsStringSync();

    // public-launch: the app is free and public, so the old alpha / tester
    // access pages are retired to noindex redirects — not real pages.
    for (final stub in [english, arabic]) {
      expect(stub, contains('name="robots" content="noindex"'));
      expect(stub, contains('http-equiv="refresh"'));
      expect(stub, isNot(contains('tester')));
    }
    expect(english, contains('url=/'));
    expect(arabic, contains('url=/ar'));
    // The join page must no longer point at a retired alpha page.
    expect(join, isNot(contains('href="/alpha"')));
  });

  test('landing pages preserve campaign source into Play referrer', () {
    final campaignScript = File('hosting/campaign.js').readAsStringSync();
    final landingPages = [
      'hosting/index.html',
      'hosting/ar.html',
      'hosting/split-bills-oman.html',
      'hosting/ar/split-bills-oman.html',
    ];

    expect(campaignScript, contains('utm_source'));
    expect(campaignScript, contains('utm_medium'));
    expect(campaignScript, contains('utm_campaign'));
    expect(campaignScript, contains("searchParams.set('referrer'"));
    expect(campaignScript, contains('play.google.com/store/apps/details'));

    for (final pagePath in landingPages) {
      final page = File(pagePath).readAsStringSync();
      expect(page, contains('<script src="/campaign.js" defer></script>'));
    }
  });

  test('landing pages use public-launch framing (no alpha/tester access)', () {
    final pages = [
      'hosting/index.html',
      'hosting/ar.html',
      'hosting/split-bills-oman.html',
      'hosting/ar/split-bills-oman.html',
    ].map((path) => File(path).readAsStringSync());

    for (final page in pages) {
      // The app is live and public — every landing page points at Google Play
      // and must not carry retired alpha / tester-access framing.
      expect(
        page,
        contains('play.google.com/store/apps/details?id=com.safar.safar'),
      );
      expect(page, isNot(contains('href="/alpha"')));
      expect(page, isNot(contains('href="/ar/alpha"')));
      expect(page, isNot(contains('Android alpha')));
      expect(page, isNot(contains('tester access')));
    }
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
