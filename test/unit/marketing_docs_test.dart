import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('short-video kit points posts to alpha and tracked install pages', () {
    final kit = File(
      'docs/marketing/short-video-content-kit.md',
    ).readAsStringSync();

    expect(kit, contains('https://rihla-safar.web.app/alpha'));
    expect(kit, contains('https://rihla-safar.web.app/ar/alpha'));
    expect(kit, contains('utm_source=instagram'));
    expect(kit, contains('utm_medium=video'));
    expect(kit, contains('video_10'));
    expect(kit, contains('dart tool/first_100_summary.dart'));
    expect(kit, isNot(contains('Download my app and let me know')));
  });

  test('operating docs link the short-video kit', () {
    final commandCenter = File(
      'docs/marketing/first-100-command-center.md',
    ).readAsStringSync();
    final outreachKit = File(
      'docs/marketing/first-100-outreach-kit.md',
    ).readAsStringSync();

    expect(commandCenter, contains('short-video-content-kit.md'));
    expect(commandCenter, contains('tool/first_100_messages.dart'));
    expect(commandCenter, contains('tool/first_100_launch_packet.dart'));
    expect(outreachKit, contains('tool/first_100_messages.dart'));
    expect(outreachKit, contains('tool/first_100_launch_packet.dart'));
    expect(commandCenter, contains('--write-roster-template'));
    expect(outreachKit, contains('--write-roster-template'));
    expect(commandCenter, contains('--play-opt-in-link'));
    expect(outreachKit, contains('--play-opt-in-link'));
    expect(outreachKit, contains('RIHLA_PLAY_OPT_IN_LINK'));
    expect(commandCenter, isNot(contains('still unshipped')));
    expect(commandCenter, isNot(contains('prioritize `#368`')));
    expect(outreachKit, contains('short-video-content-kit.md'));
    expect(outreachKit, isNot(contains('DM for access')));
  });

  test('access docs include private Play tester email export workflow', () {
    final accessKit = File(
      'docs/marketing/closed-test-access-kit.md',
    ).readAsStringSync();
    final commandCenter = File(
      'docs/marketing/first-100-command-center.md',
    ).readAsStringSync();

    expect(accessKit, contains('tool/export_play_tester_emails.dart'));
    expect(accessKit, contains('~/Desktop/rihla-first-100-play-testers.csv'));
    expect(accessKit, contains('/tmp/rihla-play-testers.csv'));
    expect(accessKit, contains('UTF-8 without a BOM'));
    expect(commandCenter, contains('tool/export_play_tester_emails.dart'));
  });

  test('public channel hit list is linked and permission-first', () {
    final commandCenter = File(
      'docs/marketing/first-100-command-center.md',
    ).readAsStringSync();
    final outreachKit = File(
      'docs/marketing/first-100-outreach-kit.md',
    ).readAsStringSync();
    final hitList = File(
      'docs/marketing/public-channel-hit-list.md',
    ).readAsStringSync();

    expect(commandCenter, contains('public-channel-hit-list.md'));
    expect(outreachKit, contains('public-channel-hit-list.md'));
    expect(hitList, contains('Do not scrape'));
    expect(hitList, contains('ask moderator permission'));
    expect(hitList, contains('utm_source=community'));
    expect(hitList, contains('InterNations Muscat'));
    expect(hitList, contains('Eventbrite Muscat'));
    expect(hitList, contains('r/Oman'));
    expect(hitList, contains('r/omantravel'));
    expect(hitList, contains('Sultan Qaboos University'));
    expect(hitList, contains('GUtech'));
    expect(hitList, contains('Oman Tourism College'));
    expect(
      hitList,
      contains(
        'https://support.google.com/googleplay/android-developer/answer/9845334',
      ),
    );
  });

  test('ASO conversion plan is linked and grounded in official guidance', () {
    final commandCenter = File(
      'docs/marketing/first-100-command-center.md',
    ).readAsStringSync();
    final asoPlan = File(
      'docs/marketing/play-store-aso-conversion-plan.md',
    ).readAsStringSync();

    expect(commandCenter, contains('play-store-aso-conversion-plan.md'));
    expect(asoPlan, contains('first-100-cohort-tracker.csv'));
    expect(asoPlan, contains('Store listing visitors'));
    expect(asoPlan, contains('First-time installers'));
    expect(asoPlan, contains('Do not start a Play experiment'));
    expect(asoPlan, contains('Variant A: current local wedge'));
    expect(asoPlan, contains('Variant B: invite-first group wedge'));
    expect(
      asoPlan,
      contains(
        'https://support.google.com/googleplay/android-developer/answer/9866151',
      ),
    );
    expect(
      asoPlan,
      contains(
        'https://play.google.com/console/about/store-listing-experiments/',
      ),
    );
    expect(
      asoPlan,
      contains(
        'https://support.google.com/googleplay/android-developer/answer/9867158',
      ),
    );
    expect(
      asoPlan,
      contains(
        'https://developers.google.com/search/docs/fundamentals/seo-starter-guide',
      ),
    );
    expect(
      asoPlan,
      contains(
        'https://developers.google.com/search/docs/specialty/international/localized-versions',
      ),
    );
    expect(asoPlan, isNot(contains('keyword stuffing')));
    expect(asoPlan, isNot(contains('buy installs')));
  });
}
