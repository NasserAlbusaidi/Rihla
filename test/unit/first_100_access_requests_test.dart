import 'package:flutter_test/flutter_test.dart';

// Tool scripts in `tool/` are not packaged; import relatively.
import '../../tool/first_100_access_requests.dart' as access_requests;

void main() {
  test(
    'builds private access asks for named champions missing Play emails',
    () {
      final result = access_requests.buildAccessRequestPacket('''
slot,champion,google_play_email,language,segment,use_case,contact_channel
1,Aisha,,en,Travel crews,Salalah trip,WhatsApp
2,Khalid,,ar,Dinner / majlis groups,Group dinner,Instagram DM
3,Maha,maha@example.com,en,Roommates / shared housing,Groceries,WhatsApp
4,,,en,Travel crews,Camping,WhatsApp
''');
      final summary = access_requests.renderSummary(result);

      expect(result.slots, ['1', '2']);
      expect(result.markdown, contains('## Slot 1 - Aisha'));
      expect(result.markdown, contains('Channel: WhatsApp'));
      expect(result.markdown, contains('which Google account'));
      expect(result.markdown, contains('## Slot 2 - Khalid'));
      expect(result.markdown, contains('ما حساب Google'));
      expect(result.markdown, isNot(contains('maha@example.com')));
      expect(summary, contains('| Access requests | 2 |'));
      expect(summary, contains('Slots needing Play email: 1, 2'));
      expect(summary, isNot(contains('Aisha')));
      expect(summary, isNot(contains('Khalid')));
      expect(summary, isNot(contains('maha@example.com')));
    },
  );

  test('reports no access asks when champion names are still blank', () {
    final result = access_requests.buildAccessRequestPacket('''
slot,champion,google_play_email,language,segment,use_case,contact_channel
1,,,en,Travel crews,Salalah trip,WhatsApp
2,,,en,Dinner / majlis groups,Group dinner,Instagram DM
''');
    final summary = access_requests.renderSummary(result);

    expect(result.slots, isEmpty);
    expect(
      result.markdown,
      contains('No named champions are missing Play emails.'),
    );
    expect(summary, contains('| Access requests | 0 |'));
    expect(
      summary,
      contains('Fill champion names before requesting Play emails.'),
    );
  });

  test('throws when required roster columns are missing', () {
    expect(
      () =>
          access_requests.buildAccessRequestPacket('slot,champion\n1,Aisha\n'),
      throwsFormatException,
    );
  });
}
