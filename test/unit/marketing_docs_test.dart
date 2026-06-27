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
    expect(outreachKit, contains('tool/first_100_messages.dart'));
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
}
