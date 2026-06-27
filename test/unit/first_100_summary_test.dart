import 'package:flutter_test/flutter_test.dart';

// Tool scripts in `tool/` are not packaged — import relatively.
import '../../tool/first_100_summary.dart' as first100;

void main() {
  const header =
      'slot,champion,segment,use_case,contact_channel,tester_added,first_contact_date,follow_up_date,group_created,invite_sent,installs_reported,joined_count,expenses_count,settlements_count,activated_group,top_blocker,feedback,next_action';

  test('summarizes first-100 tracker without exposing champion names', () {
    final rows = first100.parseTrackerCsv('''
$header
1,Aisha,Travel crews,Trip expenses,WhatsApp,yes,2026-06-27,2026-06-28,yes,yes,4,3,2,0,yes,,Great,done
2,,Dinner / majlis groups,Restaurant bill,WhatsApp,no,,,no,no,0,0,0,0,no,needs Google Play email,,fill champion name
''');

    final summary = first100.summarizeTracker(
      rows,
      today: DateTime(2026, 6, 28),
    );
    final rendered = first100.renderMarkdown(
      summary,
      today: DateTime(2026, 6, 28),
    );

    expect(summary.totalSlots, 2);
    expect(summary.namedChampions, 1);
    expect(summary.installsReported, 4);
    expect(summary.joinedUsers, 3);
    expect(summary.activatedGroups, 1);
    expect(summary.realActions, 2);
    expect(summary.nextSlots.single.slot, '2');
    expect(summary.blockers['needs Google Play email'], 1);
    expect(rendered, contains('| Named champions | 1 | 40 |'));
    expect(rendered, contains('needs Google Play email: 1'));
    expect(rendered, isNot(contains('Aisha')));
  });

  test('handles quoted CSV cells containing commas', () {
    final rows = first100.parseTrackerCsv('''
$header
1,"Champion, One",Travel crews,"Fuel, food, stay split",WhatsApp,yes,2026-06-27,2026-06-28,yes,yes,1,1,1,0,yes,"Play unavailable, wrong account",,done
''');

    final summary = first100.summarizeTracker(rows);

    expect(summary.namedChampions, 1);
    expect(summary.bySegment['Travel crews']!.slots, 1);
    expect(summary.blockers['Play unavailable, wrong account'], 1);
  });

  test(
    'recommends filling champion names before optimizing other channels',
    () {
      final rows = first100.parseTrackerCsv('''
$header
1,,Travel crews,Trip expenses,WhatsApp,no,,,no,no,0,0,0,0,no,,,fill champion name
''');

      final summary = first100.summarizeTracker(rows);

      expect(summary.nextAction, contains('Fill the first 10 champion names'));
    },
  );

  test('throws when required columns are missing', () {
    expect(
      () => first100.parseTrackerCsv('slot,champion\n1,Aisha\n'),
      throwsFormatException,
    );
  });
}
