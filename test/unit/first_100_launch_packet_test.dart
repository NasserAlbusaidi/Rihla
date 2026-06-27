import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Tool scripts in `tool/` are not packaged — import relatively.
import '../../tool/first_100_launch_packet.dart' as packet;

void main() {
  test('builds a blank launch roster template from tracker slots', () {
    final template = packet.buildLaunchRosterTemplate('''
slot,champion,segment,use_case,contact_channel,tester_added,first_contact_date,follow_up_date,group_created,invite_sent,installs_reported,joined_count,expenses_count,settlements_count,activated_group,top_blocker,feedback,next_action
1,,Travel crews,Salalah/weekend/trip expenses,WhatsApp,no,,,no,no,0,0,0,0,no,,,fill champion name and send first ask
2,Aisha,Travel crews,Camping/chalet/road trip,WhatsApp,no,,,no,no,0,0,0,0,no,,,fill champion name and send first ask
3,,Dinner / majlis groups,Restaurant bill split,Instagram DM,no,,,no,no,0,0,0,0,no,,,fill champion name and send first ask
''');

    expect(
      template,
      startsWith(
        'slot,champion,google_play_email,language,segment,use_case,contact_channel\n',
      ),
    );
    expect(
      template,
      contains('1,,,en,Travel crews,Salalah/weekend/trip expenses,WhatsApp\n'),
    );
    expect(
      template,
      contains(
        '3,,,en,Dinner / majlis groups,Restaurant bill split,Instagram DM\n',
      ),
    );
    expect(template, isNot(contains('Aisha')));
  });

  test('builds a private launch packet for mixed-language champions', () {
    final launchPacket = packet.buildLaunchPacket(
      '''
slot,champion,google_play_email,language,segment,use_case,contact_channel
1,Aisha,AISHA@GMAIL.COM,en,Travel crews,Salalah trip,WhatsApp
2,Khalid,khalid@example.com,ar,Dinner / majlis groups,Group dinner,WhatsApp
''',
      playOptInLink: 'https://play.google.com/apps/testing/com.safar.safar',
      today: DateTime(2026, 6, 27),
    );

    expect(launchPacket.playTesterCsv, 'aisha@gmail.com\nkhalid@example.com\n');
    expect(launchPacket.outreachMessages, contains('## Slot 1 - Aisha'));
    expect(launchPacket.outreachMessages, contains('## Slot 2 - Khalid'));
    expect(
      launchPacket.outreachMessages,
      contains(
        'Open this tester opt-in link first: '
        'https://play.google.com/apps/testing/com.safar.safar',
      ),
    );
    expect(
      launchPacket.outreachMessages,
      contains('utm_content=champion_slot_01'),
    );
    expect(
      launchPacket.outreachMessages,
      contains('https://rihla-safar.web.app/ar?utm_source=whatsapp'),
    );
    expect(launchPacket.checklist, contains('Date: 2026-06-27'));
    expect(launchPacket.checklist, contains('Upload `play-testers.csv`'));
    expect(launchPacket.checklist, contains('Use `send-sheet.md`'));
    expect(launchPacket.sendSheet, contains('# Rihla First-100 Send Sheet'));
    expect(launchPacket.sendSheet, contains('| 1 | Aisha | WhatsApp |'));
    expect(launchPacket.sendSheet, contains('https://wa.me/?text='));
    expect(launchPacket.sendSheet, contains('outreach-messages.md#slot-2'));
    expect(launchPacket.sendSheet, isNot(contains('AISHA@GMAIL.COM')));
    expect(launchPacket.sendSheet, isNot(contains('khalid@example.com')));
  });

  test('can include already-active Play testers in the upload CSV', () {
    final launchPacket = packet.buildLaunchPacket(
      '''
slot,champion,google_play_email,language,segment,use_case,contact_channel
1,Aisha,aisha@gmail.com,en,Travel crews,Salalah trip,WhatsApp
2,Khalid,khalid@example.com,en,Travel crews,Camping trip,WhatsApp
''',
      playOptInLink: 'https://play.google.com/apps/testing/com.safar.safar',
      existingTesterEmailsSource: '''
active@example.com
AISHA@GMAIL.COM
''',
    );

    expect(
      launchPacket.playTesterCsv,
      'active@example.com\naisha@gmail.com\nkhalid@example.com\n',
    );
    expect(
      launchPacket.checklist,
      contains('Includes 2 already-active tester emails'),
    );
  });

  test('writes launch packet files to an output directory', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'rihla-launch-packet-',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final launchPacket = packet.buildLaunchPacket('''
slot,champion,google_play_email,language,segment,use_case,contact_channel
1,Aisha,aisha@gmail.com,en,Travel crews,Trip expenses,WhatsApp
''', playOptInLink: 'https://play.google.com/apps/testing/com.safar.safar');

    await packet.writeLaunchPacket(launchPacket, tempDir.path);

    expect(
      File('${tempDir.path}/play-testers.csv').readAsStringSync(),
      'aisha@gmail.com\n',
    );
    expect(
      File('${tempDir.path}/outreach-messages.md').readAsStringSync(),
      contains('## Slot 1 - Aisha'),
    );
    expect(
      File('${tempDir.path}/checklist.md').readAsStringSync(),
      contains('Upload `play-testers.csv`'),
    );
    expect(
      File('${tempDir.path}/send-sheet.md').readAsStringSync(),
      contains('| 1 | Aisha | WhatsApp |'),
    );
  });

  test('rejects incomplete launch roster rows', () {
    expect(
      () => packet.buildLaunchPacket('''
slot,champion,google_play_email,language,segment,use_case,contact_channel
1,,aisha@gmail.com,en,Travel crews,Trip expenses,WhatsApp
''', playOptInLink: 'https://play.google.com/apps/testing/com.safar.safar'),
      throwsFormatException,
    );

    expect(
      () => packet.buildLaunchPacket('''
slot,champion,google_play_email,language,segment,use_case,contact_channel
1,Aisha,,en,Travel crews,Trip expenses,WhatsApp
''', playOptInLink: 'https://play.google.com/apps/testing/com.safar.safar'),
      throwsFormatException,
    );
  });

  test('rejects unsupported roster languages', () {
    expect(
      () => packet.buildLaunchPacket('''
slot,champion,google_play_email,language,segment,use_case,contact_channel
1,Aisha,aisha@gmail.com,fr,Travel crews,Trip expenses,WhatsApp
''', playOptInLink: 'https://play.google.com/apps/testing/com.safar.safar'),
      throwsArgumentError,
    );
  });

  test('writes a launch roster template to a private output file', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'rihla-launch-template-',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final outputPath = '${tempDir.path}/first-10.csv';

    await packet.writeLaunchRosterTemplate('''
slot,champion,segment,use_case,contact_channel,tester_added,first_contact_date,follow_up_date,group_created,invite_sent,installs_reported,joined_count,expenses_count,settlements_count,activated_group,top_blocker,feedback,next_action
1,,Travel crews,Salalah/weekend/trip expenses,WhatsApp,no,,,no,no,0,0,0,0,no,,,fill champion name and send first ask
''', outputPath);

    expect(File(outputPath).readAsStringSync(), contains('google_play_email'));
    expect(File(outputPath).readAsStringSync(), contains('Salalah/weekend'));
  });
}
