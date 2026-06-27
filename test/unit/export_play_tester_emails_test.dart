import 'package:flutter_test/flutter_test.dart';

// Tool scripts in `tool/` are not packaged — import relatively.
import '../../tool/export_play_tester_emails.dart' as exporter;

void main() {
  test('exports unique Play tester emails one per line', () {
    final export = exporter.exportTesterEmailsFromCsv('''
slot,champion,google_play_email,segment,added_to_play,opted_in,installed,notes
1,Aisha,AISHA@GMAIL.COM,Travel crews,no,no,no,
2,Khalid,khalid@example.com,Dinner / majlis groups,no,no,no,
3,Duplicate,aisha@gmail.com,Travel crews,no,no,no,
4,No email,,Travel crews,no,no,no,
''');

    expect(export.emails, ['aisha@gmail.com', 'khalid@example.com']);
    expect(export.skippedBlankRows, 1);
    expect(
      exporter.renderPlayTesterCsv(export),
      'aisha@gmail.com\nkhalid@example.com\n',
    );
  });

  test('supports a custom email column', () {
    final export = exporter.exportTesterEmailsFromCsv('''
name,email
Aisha,aisha@gmail.com
''', emailColumn: 'email');

    expect(export.emails, ['aisha@gmail.com']);
  });

  test('rejects missing email column', () {
    expect(
      () => exporter.exportTesterEmailsFromCsv('slot,champion\n1,Aisha\n'),
      throwsFormatException,
    );
  });

  test('rejects invalid email values before Play upload', () {
    expect(
      () => exporter.exportTesterEmailsFromCsv('''
slot,google_play_email
1,not an email
'''),
      throwsFormatException,
    );
  });
}
