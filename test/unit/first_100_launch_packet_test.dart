import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Tool scripts in `tool/` are not packaged — import relatively.
import '../../tool/first_100_launch_packet.dart' as packet;

void main() {
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
    expect(launchPacket.checklist, contains('Send `outreach-messages.md`'));
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
}
