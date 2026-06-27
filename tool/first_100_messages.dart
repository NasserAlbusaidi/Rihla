// tool/first_100_messages.dart
//
// Generates slot-specific first-100 outreach messages from the public tracker.
//
// Run via:
//   dart tool/first_100_messages.dart
//   dart tool/first_100_messages.dart --count=10 --language=ar

import 'dart:io';

import 'first_100_summary.dart' as first100;

const defaultCount = 10;
const _baseUrl = 'https://rihla-safar.web.app';

class OutreachMessage {
  OutreachMessage({
    required this.slot,
    required this.segment,
    required this.useCase,
    required this.channel,
    required this.link,
    required this.body,
  });

  final String slot;
  final String segment;
  final String useCase;
  final String channel;
  final String link;
  final String body;
}

List<Map<String, String>> selectUncontactedRows(
  List<Map<String, String>> rows, {
  int count = defaultCount,
}) {
  return rows
      .where((row) => (row['first_contact_date'] ?? '').trim().isEmpty)
      .take(count)
      .toList(growable: false);
}

List<OutreachMessage> buildOutreachMessages(
  List<Map<String, String>> rows, {
  String language = 'en',
  int count = defaultCount,
}) {
  final normalizedLanguage = language.toLowerCase();
  if (normalizedLanguage != 'en' && normalizedLanguage != 'ar') {
    throw ArgumentError.value(language, 'language', 'Use en or ar.');
  }

  return selectUncontactedRows(rows, count: count)
      .map((row) {
        final slot = (row['slot'] ?? '').trim();
        final segment = (row['segment'] ?? '').trim();
        final useCase = (row['use_case'] ?? '').trim();
        final channel = (row['contact_channel'] ?? '').trim();
        final link = buildTrackedLink(
          slot: slot,
          channel: channel,
          language: normalizedLanguage,
        );
        return OutreachMessage(
          slot: slot,
          segment: segment,
          useCase: useCase,
          channel: channel,
          link: link,
          body: normalizedLanguage == 'ar'
              ? _arabicMessage(link)
              : _englishMessage(link),
        );
      })
      .toList(growable: false);
}

String buildTrackedLink({
  required String slot,
  required String channel,
  required String language,
}) {
  final source = channel.toLowerCase().contains('instagram')
      ? 'instagram'
      : 'whatsapp';
  final campaign = language == 'ar' ? 'first_100_ar' : 'first_100';
  final path = language == 'ar' ? '/ar' : '/';
  final normalizedSlot = slot.padLeft(2, '0');
  final params = Uri(
    queryParameters: {
      'utm_source': source,
      'utm_medium': 'dm',
      'utm_campaign': campaign,
      'utm_content': 'champion_slot_$normalizedSlot',
    },
  ).query;

  return '$_baseUrl$path?$params';
}

String renderMessageBatch(List<OutreachMessage> messages) {
  if (messages.isEmpty) {
    return 'No uncontacted tracker rows found.\n';
  }

  final buffer = StringBuffer('# Rihla First-100 Outreach Messages\n\n');
  for (final message in messages) {
    buffer
      ..writeln('## Slot ${message.slot}')
      ..writeln()
      ..writeln('- Segment: ${message.segment}')
      ..writeln('- Use case: ${message.useCase}')
      ..writeln('- Channel: ${message.channel}')
      ..writeln('- Trackable link: ${message.link}')
      ..writeln()
      ..writeln('```text')
      ..writeln(message.body)
      ..writeln('```')
      ..writeln();
  }
  return buffer.toString();
}

Future<void> main(List<String> args) async {
  var trackerPath = first100.defaultTrackerPath;
  var count = defaultCount;
  var language = 'en';

  for (final arg in args) {
    if (arg.startsWith('--count=')) {
      count = int.parse(arg.substring('--count='.length));
    } else if (arg.startsWith('--language=')) {
      language = arg.substring('--language='.length);
    } else if (!arg.startsWith('--')) {
      trackerPath = arg;
    }
  }

  if (count < 1) {
    stderr.writeln('count must be at least 1');
    exit(64);
  }

  final source = await File(trackerPath).readAsString();
  final rows = first100.parseTrackerCsv(source);
  final messages = buildOutreachMessages(
    rows,
    count: count,
    language: language,
  );
  stdout.write(renderMessageBatch(messages));
}

String _englishMessage(String link) {
  return '''
Can you use Rihla for one real shared bill this week?

Best case: a trip, dinner, groceries, fuel, or a booking where one person pays for the group.

Create a group, send the WhatsApp invite, and add the first expense while it is fresh. I need real usage, not compliments.

Link: $link

If you install from a group invite and the code is not filled automatically, go back to the WhatsApp invite link and tap it again after installing.''';
}

String _arabicMessage(String link) {
  return '''
ممكن تستخدم Rihla لمصاريف مجموعة حقيقية هذا الأسبوع؟

أفضل تجربة: رحلة، عشاء، مشتريات، بترول، أو حجز يدفعه شخص عن المجموعة.

أنشئ مجموعة، أرسل دعوة واتساب، وأضف أول مصروف وهو لا يزال جديد. أحتاج استخدام حقيقي، وليس مجاملة.

الرابط: $link

إذا ثبت التطبيق من رابط دعوة ولم يظهر رمز المجموعة تلقائيًا، ارجع إلى رابط الدعوة في واتساب وافتحه مرة ثانية بعد التثبيت.''';
}
