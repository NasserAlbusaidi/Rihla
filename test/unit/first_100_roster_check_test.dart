import 'package:flutter_test/flutter_test.dart';

// Tool scripts in `tool/` are not packaged — import relatively.
import '../../tool/first_100_roster_check.dart' as roster_check;

void main() {
  test('marks a complete private launch roster ready without exposing PII', () {
    final result = roster_check.checkLaunchRoster('''
slot,champion,google_play_email,language,segment,use_case,contact_channel
1,Aisha,aisha@gmail.com,en,Travel crews,Salalah trip,WhatsApp
2,Khalid,khalid@example.com,ar,Dinner / majlis groups,Group dinner,WhatsApp
''');
    final rendered = roster_check.renderMarkdown(result);

    expect(result.readyRows, 2);
    expect(result.issueRows, isEmpty);
    expect(rendered, contains('| Ready rows | 2 |'));
    expect(rendered, contains('Roster is ready for launch packet generation.'));
    expect(rendered, isNot(contains('Aisha')));
    expect(rendered, isNot(contains('Khalid')));
    expect(rendered, isNot(contains('aisha@gmail.com')));
    expect(rendered, isNot(contains('khalid@example.com')));
  });

  test('reports missing fields by slot without exposing names or emails', () {
    final result = roster_check.checkLaunchRoster('''
slot,champion,google_play_email,language,segment,use_case,contact_channel
1,,aisha@gmail.com,en,Travel crews,Salalah trip,WhatsApp
2,Khalid,,en,Travel crews,Camping trip,WhatsApp
3,Maha,maha@example.com,fr,Dinner / majlis groups,Group dinner,Instagram DM
4,Noor,not-an-email,en,Roommates / shared housing,Groceries,WhatsApp
5,Salim,salim@example.com,en,,Fuel split,WhatsApp
6,Lina,salim@example.com,ar,Travel crews,Weekend outing,
''');
    final rendered = roster_check.renderMarkdown(result);

    expect(result.readyRows, 0);
    expect(result.issueRows.length, 6);
    expect(rendered, contains('| 1 | missing champion |'));
    expect(rendered, contains('| 2 | missing google_play_email |'));
    expect(rendered, contains('| 3 | unsupported language |'));
    expect(rendered, contains('| 4 | invalid google_play_email |'));
    expect(rendered, contains('| 5 | missing segment |'));
    expect(
      rendered,
      contains('| 6 | duplicate google_play_email, missing contact_channel |'),
    );
    expect(rendered, isNot(contains('Khalid')));
    expect(rendered, isNot(contains('maha@example.com')));
    expect(rendered, isNot(contains('salim@example.com')));
  });

  test(
    'rejects a comma-bearing email the Play tester exporter would also '
    'reject (#743)',
    () {
      final result = roster_check.checkLaunchRoster('''
slot,champion,google_play_email,language,segment,use_case,contact_channel
1,Aisha,"tester+one,two@example.com",en,Travel crews,Salalah trip,WhatsApp
''');

      expect(result.readyRows, 0);
      expect(result.issueRows.single.issues, contains('invalid google_play_email'));
    },
  );

  test('throws when roster columns are missing', () {
    expect(
      () => roster_check.checkLaunchRoster('slot,champion\n1,Aisha\n'),
      throwsFormatException,
    );
  });
}
