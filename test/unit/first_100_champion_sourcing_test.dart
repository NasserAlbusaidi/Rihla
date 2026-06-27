import 'package:flutter_test/flutter_test.dart';

// Tool scripts in `tool/` are not packaged; import relatively.
import '../../tool/first_100_champion_sourcing.dart' as sourcing;

void main() {
  const trackerHeader =
      'slot,champion,segment,use_case,contact_channel,tester_added,first_contact_date,follow_up_date,group_created,invite_sent,installs_reported,joined_count,expenses_count,settlements_count,activated_group,top_blocker,feedback,next_action';

  test('builds a private candidate worksheet from empty tracker slots', () {
    final worksheet = sourcing.buildSourcingWorksheetTemplate('''
$trackerHeader
1,,Travel crews,Salalah trip,WhatsApp,no,,,no,no,0,0,0,0,no,,,fill champion name
2,Aisha,Travel crews,Camping,WhatsApp,no,,,no,no,0,0,0,0,no,,,send launch packet
3,,Dinner / majlis groups,Restaurant bill,Instagram DM,no,,,no,no,0,0,0,0,no,,,fill champion name
''');

    expect(
      worksheet,
      startsWith(
        'slot,candidate,relationship,language,segment,use_case,contact_channel,android_likely,group_size_estimate,has_live_bill,priority,next_action,notes\n',
      ),
    );
    expect(
      worksheet,
      contains(
        '1,,,en,Travel crews,Salalah trip,WhatsApp,unknown,,unknown,,identify and ask champion,',
      ),
    );
    expect(
      worksheet,
      contains(
        '3,,,en,Dinner / majlis groups,Restaurant bill,Instagram DM,unknown,,unknown,,identify and ask champion,',
      ),
    );
    expect(worksheet, isNot(contains('Aisha')));
  });

  test('checks candidate readiness without exposing private names', () {
    final result = sourcing.checkSourcingWorksheet('''
slot,candidate,relationship,language,segment,use_case,contact_channel,android_likely,group_size_estimate,has_live_bill,priority,next_action,notes
1,Aisha,cousin,en,Travel crews,Salalah trip,WhatsApp,yes,5,yes,1,ask for Play email,uses Android
2,Khalid,colleague,en,Coworkers / student groups,Office lunch,WhatsApp,unknown,4,yes,2,confirm Android,
3,Maha,friend,ar,Dinner / majlis groups,Restaurant bill,Instagram DM,yes,1,yes,1,find larger group,
4,Noor,,fr,Roommates / shared housing,Groceries,WhatsApp,yes,3,no,high,,
''');
    final rendered = sourcing.renderSummary(result);

    expect(result.readySlots, ['1']);
    expect(result.issueRows.length, 3);
    expect(rendered, contains('| Candidate rows | 4 |'));
    expect(rendered, contains('| Ready for access request | 1 |'));
    expect(rendered, contains('Ready slots: 1'));
    expect(rendered, contains('| 2 | android_likely is not yes |'));
    expect(rendered, contains('| 3 | group_size_estimate below 2 |'));
    expect(
      rendered,
      contains(
        '| 4 | missing relationship, unsupported language, has_live_bill is not yes, unsupported priority |',
      ),
    );
    expect(rendered, isNot(contains('Aisha')));
    expect(rendered, isNot(contains('Khalid')));
    expect(rendered, isNot(contains('Maha')));
    expect(rendered, isNot(contains('Noor')));
  });

  test('promotes ready candidates into the launch roster format', () {
    final roster = sourcing.buildLaunchRosterFromSourcingWorksheet('''
slot,candidate,relationship,language,segment,use_case,contact_channel,android_likely,group_size_estimate,has_live_bill,priority,next_action,notes
1,Aisha,cousin,en,Travel crews,Salalah trip,WhatsApp,yes,5,yes,1,ask for Play email,uses Android
2,Khalid,colleague,en,Coworkers / student groups,Office lunch,WhatsApp,unknown,4,yes,2,confirm Android,
3,Maha,friend,ar,Dinner / majlis groups,Restaurant bill,Instagram DM,yes,3,yes,1,ask for Play email,
''');

    expect(
      roster,
      'slot,champion,google_play_email,language,segment,use_case,contact_channel\n'
      '1,Aisha,,en,Travel crews,Salalah trip,WhatsApp\n'
      '3,Maha,,ar,Dinner / majlis groups,Restaurant bill,Instagram DM\n',
    );
    expect(roster, isNot(contains('Khalid')));
  });

  test('throws when required sourcing columns are missing', () {
    expect(
      () => sourcing.checkSourcingWorksheet('slot,candidate\n1,Aisha\n'),
      throwsFormatException,
    );
  });
}
