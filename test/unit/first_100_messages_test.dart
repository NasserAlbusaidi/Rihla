import 'package:flutter_test/flutter_test.dart';

// Tool scripts in `tool/` are not packaged — import relatively.
import '../../tool/first_100_messages.dart' as messages;
import '../../tool/first_100_summary.dart' as first100;

void main() {
  const header =
      'slot,champion,segment,use_case,contact_channel,tester_added,first_contact_date,follow_up_date,group_created,invite_sent,installs_reported,joined_count,expenses_count,settlements_count,activated_group,top_blocker,feedback,next_action';

  test(
    'generates English outreach messages with slot-specific tracked links',
    () {
      final rows = first100.parseTrackerCsv('''
$header
1,,Travel crews,Trip expenses,WhatsApp,no,,,no,no,0,0,0,0,no,,,fill champion name
9,,Travel crews,Weekend outing,Instagram DM,no,,,no,no,0,0,0,0,no,,,fill champion name
''');

      final batch = messages.buildOutreachMessages(rows, count: 2);
      final rendered = messages.renderMessageBatch(batch);

      expect(batch, hasLength(2));
      expect(
        batch.first.link,
        'https://rihla-safar.web.app/?utm_source=whatsapp&utm_medium=dm'
        '&utm_campaign=first_100&utm_content=champion_slot_01',
      );
      expect(
        batch.last.link,
        'https://rihla-safar.web.app/?utm_source=instagram&utm_medium=dm'
        '&utm_campaign=first_100&utm_content=champion_slot_09',
      );
      expect(rendered, contains('Can you use Rihla for one real shared bill'));
      expect(rendered, isNot(contains('SLOT_LINK')));
    },
  );

  test('generates Arabic outreach messages with Arabic landing links', () {
    final rows = first100.parseTrackerCsv('''
$header
2,,Travel crews,Trip expenses,WhatsApp,no,,,no,no,0,0,0,0,no,,,fill champion name
''');

    final batch = messages.buildOutreachMessages(rows, language: 'ar');
    final rendered = messages.renderMessageBatch(batch);

    expect(
      batch.single.link,
      'https://rihla-safar.web.app/ar?utm_source=whatsapp&utm_medium=dm'
      '&utm_campaign=first_100_ar&utm_content=champion_slot_02',
    );
    expect(rendered, contains('ممكن تستخدم Rihla'));
  });

  test('skips already-contacted rows', () {
    final rows = first100.parseTrackerCsv('''
$header
1,,Travel crews,Trip expenses,WhatsApp,no,2026-06-27,2026-06-28,no,no,0,0,0,0,no,,,sent
2,,Travel crews,Trip expenses,WhatsApp,no,,,no,no,0,0,0,0,no,,,fill champion name
''');

    final batch = messages.buildOutreachMessages(rows);

    expect(batch, hasLength(1));
    expect(batch.single.slot, '2');
  });

  test('rejects unsupported languages', () {
    expect(
      () => messages.buildOutreachMessages(const [], language: 'fr'),
      throwsArgumentError,
    );
  });
}
