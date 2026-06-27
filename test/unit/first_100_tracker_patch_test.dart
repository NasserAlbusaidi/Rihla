import 'package:flutter_test/flutter_test.dart';

// Tool scripts in `tool/` are not packaged; import relatively.
import '../../tool/first_100_summary.dart' as first100;
import '../../tool/first_100_tracker_patch.dart' as tracker_patch;

void main() {
  const trackerHeader =
      'slot,champion,segment,use_case,contact_channel,tester_added,first_contact_date,follow_up_date,group_created,invite_sent,installs_reported,joined_count,expenses_count,settlements_count,activated_group,top_blocker,feedback,next_action';

  test('applies a private launch roster without carrying Play emails', () {
    final result = tracker_patch.applyLaunchRosterToTracker(
      '''
$trackerHeader
1,,Travel crews,Old trip,WhatsApp,no,,,no,no,0,0,0,0,no,,,fill champion name
2,,Dinner / majlis groups,Old dinner,Instagram DM,no,,,no,no,0,0,0,0,no,,,fill champion name
3,,Travel crews,Already named,WhatsApp,no,,,no,no,0,0,0,0,no,,,keep existing
''',
      '''
slot,champion,google_play_email,language,segment,use_case,contact_channel
1,Aisha,aisha@gmail.com,en,Travel crews,Salalah trip,WhatsApp
2,Khalid,khalid@example.com,ar,Dinner / majlis groups,Group dinner,Instagram DM
''',
      today: DateTime(2026, 6, 27),
      markTesterAdded: true,
      markContacted: true,
    );

    final rows = first100.parseTrackerCsv(result.trackerCsv);
    final first = rows.firstWhere((row) => row['slot'] == '1');
    final second = rows.firstWhere((row) => row['slot'] == '2');
    final third = rows.firstWhere((row) => row['slot'] == '3');
    final rendered = tracker_patch.renderMarkdown(result);

    expect(first['champion'], 'Aisha');
    expect(first['tester_added'], 'yes');
    expect(first['first_contact_date'], '2026-06-27');
    expect(first['follow_up_date'], '2026-06-28');
    expect(first['top_blocker'], isEmpty);
    expect(first['next_action'], 'follow up after first ask');
    expect(second['contact_channel'], 'Instagram DM');
    expect(second['use_case'], 'Group dinner');
    expect(third['champion'], isEmpty);
    expect(result.updatedSlots, ['1', '2']);
    expect(result.trackerCsv, isNot(contains('gmail.com')));
    expect(result.trackerCsv, isNot(contains('example.com')));
    expect(rendered, contains('| Updated slots | 2 |'));
    expect(rendered, contains('Slots updated: 1, 2'));
    expect(rendered, isNot(contains('Aisha')));
    expect(rendered, isNot(contains('khalid@example.com')));
  });

  test('throws when a roster slot is not present in the tracker', () {
    expect(
      () => tracker_patch.applyLaunchRosterToTracker(
        '''
$trackerHeader
1,,Travel crews,Trip,WhatsApp,no,,,no,no,0,0,0,0,no,,,fill champion name
''',
        '''
slot,champion,google_play_email,language,segment,use_case,contact_channel
99,Aisha,aisha@gmail.com,en,Travel crews,Trip,WhatsApp
''',
        today: DateTime(2026, 6, 27),
      ),
      throwsFormatException,
    );
  });
}
