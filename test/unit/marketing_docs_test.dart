import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Closed-alpha tokens that must never return to the operating docs now that
// v1.6.3 is in public production (2026-06-28). See closed-test-access-kit.md.
const _closedAlphaTokens = <String>[
  '--play-opt-in-link',
  'RIHLA_PLAY_OPT_IN_LINK',
  '--include-existing-testers',
  'tool/export_play_tester_emails.dart',
  'tool/first_100_access_requests.dart',
];

void main() {
  test('short-video kit points posts to the public Play listing, not alpha', () {
    final kit = File(
      'docs/marketing/short-video-content-kit.md',
    ).readAsStringSync();

    expect(kit, contains('Install from the public Play'));
    expect(kit, contains('utm_source=instagram'));
    expect(kit, contains('utm_medium=video'));
    expect(kit, contains('video_10'));
    expect(kit, contains('dart tool/first_100_summary.dart'));
    expect(kit, isNot(contains('Download my app and let me know')));
    // Public production: the closed-test /alpha access pages are not an install
    // path anymore.
    expect(kit, isNot(contains('rihla-safar.web.app/alpha')));
    expect(kit, isNot(contains('rihla-safar.web.app/ar/alpha')));
  });

  test('operating docs reference live tools and cross-link, no closed-alpha steps', () {
    final commandCenter = File(
      'docs/marketing/first-100-command-center.md',
    ).readAsStringSync();
    final outreachKit = File(
      'docs/marketing/first-100-outreach-kit.md',
    ).readAsStringSync();

    for (final doc in [commandCenter, outreachKit]) {
      expect(doc, contains('short-video-content-kit.md'));
      expect(doc, contains('tool/first_100_messages.dart'));
      expect(doc, contains('tool/first_100_launch_packet.dart'));
      expect(doc, contains('tool/first_100_followups.dart'));
      expect(doc, contains('tool/first_100_roster_check.dart'));
      expect(doc, contains('tool/first_100_tracker_patch.dart'));
      expect(doc, contains('tool/play_acquisition_summary.dart'));
      expect(doc, contains('tool/first_100_champion_sourcing.dart'));
      expect(doc, contains('rihla-first-10-candidates.csv'));
      expect(doc, contains('rihla-first-100-tracker.csv'));
      expect(doc, contains('--write-roster-template'));
      expect(doc, contains('send-sheet.md'));
      // The closed-alpha access funnel was removed; it must not creep back.
      for (final token in _closedAlphaTokens) {
        expect(doc, isNot(contains(token)), reason: '$token must stay out');
      }
    }

    expect(commandCenter, isNot(contains('still unshipped')));
    expect(commandCenter, isNot(contains('prioritize `#368`')));
    expect(outreachKit, isNot(contains('DM for access')));
  });

  test('closed-test access kit is an obsolete tombstone pointing to the live loop', () {
    final accessKit = File(
      'docs/marketing/closed-test-access-kit.md',
    ).readAsStringSync();
    final commandCenter = File(
      'docs/marketing/first-100-command-center.md',
    ).readAsStringSync();

    expect(accessKit, contains('OBSOLETE'));
    expect(accessKit, contains('public production'));
    expect(accessKit, contains('first-100-command-center.md'));
    expect(accessKit, contains('day-1-outreach.md'));
    // The closed-test export workflow is gone from both the kit and the hub.
    expect(accessKit, isNot(contains('tool/export_play_tester_emails.dart')));
    expect(accessKit, isNot(contains('--include-existing')));
    expect(commandCenter, isNot(contains('tool/export_play_tester_emails.dart')));
    expect(commandCenter, isNot(contains('--include-existing-testers=')));
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
    expect(asoPlan, contains('tool/play_acquisition_summary.dart'));
    expect(asoPlan, contains('--write-template'));
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
