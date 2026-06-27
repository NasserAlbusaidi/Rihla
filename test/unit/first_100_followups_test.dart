import 'package:flutter_test/flutter_test.dart';

// Tool scripts in `tool/` are not packaged — import relatively.
import '../../tool/first_100_followups.dart' as followups;
import '../../tool/first_100_summary.dart' as first100;

void main() {
  const header =
      'slot,champion,segment,use_case,contact_channel,tester_added,first_contact_date,follow_up_date,group_created,invite_sent,installs_reported,joined_count,expenses_count,settlements_count,activated_group,top_blocker,feedback,next_action';

  test('renders due follow-up prompts without exposing champion names', () {
    final rows = first100.parseTrackerCsv('''
$header
1,Aisha,Travel crews,Trip expenses,WhatsApp,no,2026-06-26,2026-06-27,no,no,0,0,0,0,no,,,follow up on Play access
2,Khalid,Dinner / majlis groups,Restaurant bill,WhatsApp,yes,2026-06-26,2026-06-27,no,no,0,0,0,0,no,,,follow up on install
3,Maha,Roommates / shared housing,Groceries,WhatsApp,yes,2026-06-26,2026-06-27,no,no,1,0,0,0,no,,,follow up on first group
4,Noor,Travel crews,Trip expenses,WhatsApp,yes,2026-06-26,2026-06-27,yes,yes,4,3,2,0,yes,,,done
5,Salim,Travel crews,Trip expenses,WhatsApp,yes,2026-06-26,2026-06-30,no,no,0,0,0,0,no,,,not due yet
''');

    final prompts = followups.buildFollowUpPrompts(
      rows,
      today: DateTime(2026, 6, 27),
    );
    final rendered = followups.renderFollowUpPrompts(
      prompts,
      today: DateTime(2026, 6, 27),
    );

    expect(prompts, hasLength(3));
    expect(rendered, contains('# Rihla First-100 Follow-Up Prompts'));
    expect(rendered, contains('## Slot 1 - Tester access'));
    expect(rendered, contains('## Slot 2 - Install'));
    expect(rendered, contains('## Slot 3 - Create the group'));
    expect(rendered, contains('Confirm the Google Play account'));
    expect(rendered, contains('Open the tester opt-in link'));
    expect(rendered, contains('create the Rihla group'));
    expect(rendered, isNot(contains('Aisha')));
    expect(rendered, isNot(contains('Khalid')));
    expect(rendered, isNot(contains('Maha')));
    expect(rendered, isNot(contains('Noor')));
    expect(rendered, isNot(contains('Salim')));
  });

  test('renders an empty state when no follow-ups are due', () {
    final rows = first100.parseTrackerCsv('''
$header
1,Aisha,Travel crews,Trip expenses,WhatsApp,yes,2026-06-26,2026-06-30,no,no,0,0,0,0,no,,,not due yet
''');

    final prompts = followups.buildFollowUpPrompts(
      rows,
      today: DateTime(2026, 6, 27),
    );

    expect(prompts, isEmpty);
    expect(
      followups.renderFollowUpPrompts(prompts, today: DateTime(2026, 6, 27)),
      'No due first-100 follow-ups found.\n',
    );
  });
}
