// tool/first_100_launch_packet.dart
//
// Builds a private first-100 launch packet from a local roster CSV. The output
// contains Play tester emails, paste-ready outreach messages, a send sheet, and
// an operator checklist. Keep the input and generated output outside git.
//
// Run via:
//   dart tool/first_100_launch_packet.dart ~/Desktop/rihla-first-10.csv \
//     --play-opt-in-link="$RIHLA_PLAY_OPT_IN_LINK" \
//     --include-existing-testers=~/Desktop/rihla-active-play-testers.csv \
//     --output-dir=/tmp/rihla-first-10-launch-packet

import 'dart:io';

import 'export_play_tester_emails.dart' as email_exporter;
import 'first_100_messages.dart' as messages;
import 'first_100_summary.dart' as first100;

const requiredLaunchRosterColumns = [
  'slot',
  'champion',
  'google_play_email',
  'language',
  'segment',
  'use_case',
  'contact_channel',
];

class LaunchPacket {
  LaunchPacket({
    required this.playTesterCsv,
    required this.outreachMessages,
    required this.sendSheet,
    required this.checklist,
  });

  final String playTesterCsv;
  final String outreachMessages;
  final String sendSheet;
  final String checklist;
}

class LaunchRosterEntry {
  LaunchRosterEntry({
    required this.slot,
    required this.champion,
    required this.language,
    required this.segment,
    required this.useCase,
    required this.contactChannel,
  });

  final String slot;
  final String champion;
  final String language;
  final String segment;
  final String useCase;
  final String contactChannel;
}

String buildLaunchRosterTemplate(String trackerCsv, {int count = 10}) {
  final rows = first100.parseTrackerCsv(trackerCsv);
  final buffer = StringBuffer()..writeln(requiredLaunchRosterColumns.join(','));

  for (final row
      in rows
          .where((row) => (row['champion'] ?? '').trim().isEmpty)
          .take(count)) {
    buffer.writeln(
      [
        row['slot'] ?? '',
        '',
        '',
        'en',
        row['segment'] ?? '',
        row['use_case'] ?? '',
        row['contact_channel'] ?? '',
      ].map(_csvCell).join(','),
    );
  }

  return buffer.toString();
}

Future<void> writeLaunchRosterTemplate(
  String trackerCsv,
  String outputPath, {
  int count = 10,
}) async {
  await File(
    outputPath,
  ).writeAsString(buildLaunchRosterTemplate(trackerCsv, count: count));
}

LaunchPacket buildLaunchPacket(
  String rosterCsv, {
  required String playOptInLink,
  String? existingTesterEmailsSource,
  DateTime? today,
}) {
  final entries = parseLaunchRoster(rosterCsv);
  final emailExport = email_exporter.exportTesterEmailsFromCsv(
    rosterCsv,
    existingEmailsSource: existingTesterEmailsSource,
  );
  final outreachMessages = _renderOutreachMessages(
    entries,
    playOptInLink: playOptInLink,
  );
  final sendSheet = _renderSendSheet(entries, playOptInLink: playOptInLink);
  final checklist = _renderChecklist(
    entries,
    today: today,
    testerCount: emailExport.emails.length,
    includedExistingEmails: emailExport.includedExistingEmails,
  );

  return LaunchPacket(
    playTesterCsv: email_exporter.renderPlayTesterCsv(emailExport),
    outreachMessages: outreachMessages,
    sendSheet: sendSheet,
    checklist: checklist,
  );
}

List<LaunchRosterEntry> parseLaunchRoster(String source) {
  final rows = _parseCsv(source);
  if (rows.isEmpty) {
    throw const FormatException('launch roster CSV is empty');
  }

  final header = rows.first.map((cell) => cell.trim()).toList(growable: false);
  final missing = requiredLaunchRosterColumns.where(
    (column) => !header.contains(column),
  );
  if (missing.isNotEmpty) {
    throw FormatException(
      'launch roster missing columns: ${missing.join(', ')}',
    );
  }

  final entries = <LaunchRosterEntry>[];
  for (final row in rows.skip(1)) {
    if (row.every((cell) => cell.trim().isEmpty)) {
      continue;
    }

    String field(String column) {
      final index = header.indexOf(column);
      return index < row.length ? row[index].trim() : '';
    }

    final slot = field('slot');
    final champion = field('champion');
    final email = field('google_play_email');
    final language = field('language').toLowerCase();
    final segment = field('segment');
    final useCase = field('use_case');
    final contactChannel = field('contact_channel');

    if (slot.isEmpty) {
      throw const FormatException('launch roster row missing slot');
    }
    if (champion.isEmpty) {
      throw FormatException('launch roster slot $slot missing champion');
    }
    if (email.isEmpty) {
      throw FormatException(
        'launch roster slot $slot missing google_play_email',
      );
    }
    if (language != 'en' && language != 'ar') {
      throw ArgumentError.value(language, 'language', 'Use en or ar.');
    }
    if (segment.isEmpty || useCase.isEmpty || contactChannel.isEmpty) {
      throw FormatException(
        'launch roster slot $slot missing outreach context',
      );
    }

    entries.add(
      LaunchRosterEntry(
        slot: slot,
        champion: champion,
        language: language,
        segment: segment,
        useCase: useCase,
        contactChannel: contactChannel,
      ),
    );
  }

  if (entries.isEmpty) {
    throw const FormatException('launch roster has no usable rows');
  }
  return entries;
}

Future<void> writeLaunchPacket(LaunchPacket packet, String outputDir) async {
  final directory = Directory(outputDir);
  await directory.create(recursive: true);
  await File(
    '${directory.path}/play-testers.csv',
  ).writeAsString(packet.playTesterCsv);
  await File(
    '${directory.path}/outreach-messages.md',
  ).writeAsString(packet.outreachMessages);
  await File('${directory.path}/send-sheet.md').writeAsString(packet.sendSheet);
  await File('${directory.path}/checklist.md').writeAsString(packet.checklist);
}

Future<void> main(List<String> args) async {
  String? inputPath;
  String? outputDir;
  String? templateOutputPath;
  String? existingTestersPath;
  var playOptInLink = Platform.environment['RIHLA_PLAY_OPT_IN_LINK'];
  var templateCount = 10;

  for (final arg in args) {
    if (arg.startsWith('--output-dir=')) {
      outputDir = arg.substring('--output-dir='.length);
    } else if (arg.startsWith('--include-existing-testers=')) {
      existingTestersPath = arg.substring('--include-existing-testers='.length);
    } else if (arg.startsWith('--write-roster-template=')) {
      templateOutputPath = arg.substring('--write-roster-template='.length);
    } else if (arg.startsWith('--template-count=')) {
      templateCount = int.parse(arg.substring('--template-count='.length));
    } else if (arg.startsWith('--play-opt-in-link=')) {
      playOptInLink = arg.substring('--play-opt-in-link='.length);
    } else if (!arg.startsWith('--')) {
      inputPath = arg;
    }
  }

  if (templateOutputPath != null) {
    final trackerPath = inputPath ?? first100.defaultTrackerPath;
    final trackerCsv = await File(trackerPath).readAsString();
    await writeLaunchRosterTemplate(
      trackerCsv,
      templateOutputPath,
      count: templateCount,
    );
    stderr.writeln('Wrote launch roster template to $templateOutputPath');
    return;
  }

  if (inputPath == null || outputDir == null || playOptInLink == null) {
    stderr.writeln(
      'Usage: dart tool/first_100_launch_packet.dart <private-roster.csv> '
      '--play-opt-in-link=<https-url> --output-dir=<private-output-dir> '
      '[--include-existing-testers=<one-email-per-line-file>]\n'
      '   or: dart tool/first_100_launch_packet.dart '
      '[tracker.csv] --write-roster-template=<private-roster.csv> '
      '[--template-count=10]',
    );
    exit(64);
  }

  final rosterCsv = await File(inputPath).readAsString();
  final existingTesterEmailsSource = existingTestersPath == null
      ? null
      : await File(existingTestersPath).readAsString();
  final packet = buildLaunchPacket(
    rosterCsv,
    playOptInLink: playOptInLink,
    existingTesterEmailsSource: existingTesterEmailsSource,
  );
  await writeLaunchPacket(packet, outputDir);
  stderr.writeln('Wrote first-100 launch packet to $outputDir');
}

String _renderOutreachMessages(
  List<LaunchRosterEntry> entries, {
  required String playOptInLink,
}) {
  final buffer = StringBuffer('# Rihla First-100 Launch Messages\n\n');

  for (final entry in entries) {
    final built = _buildMessage(entry, playOptInLink: playOptInLink);

    buffer
      ..writeln('## Slot ${entry.slot} - ${entry.champion}')
      ..writeln()
      ..writeln('- Segment: ${entry.segment}')
      ..writeln('- Use case: ${entry.useCase}')
      ..writeln('- Channel: ${entry.contactChannel}')
      ..writeln('- Language: ${entry.language}')
      ..writeln('- Trackable link: ${built.link}')
      ..writeln()
      ..writeln('```text')
      ..writeln(built.body)
      ..writeln('```')
      ..writeln();
  }
  return buffer.toString();
}

String _renderSendSheet(
  List<LaunchRosterEntry> entries, {
  required String playOptInLink,
}) {
  final buffer = StringBuffer()
    ..writeln('# Rihla First-100 Send Sheet')
    ..writeln()
    ..writeln(
      'Use after `play-testers.csv` is uploaded and the Play opt-in link opens.',
    )
    ..writeln()
    ..writeln(
      '| Slot | Champion | Channel | Language | Tracked link | Message | Send action |',
    )
    ..writeln('|---:|---|---|---|---|---|---|');

  for (final entry in entries) {
    final built = _buildMessage(entry, playOptInLink: playOptInLink);
    final messageLink = 'outreach-messages.md#slot-${entry.slot}';
    final sendAction = _sendAction(entry, built.body);

    final cells = [
      entry.slot,
      entry.champion,
      entry.contactChannel,
      entry.language,
      '[Link](${built.link})',
      '[Copy]($messageLink)',
      sendAction,
    ].map(_markdownCell).join(' | ');

    buffer.writeln('| $cells |');
  }

  buffer
    ..writeln()
    ..writeln(
      'After sending, set `first_contact_date` and next-day `follow_up_date` in the private tracker.',
    );
  return buffer.toString();
}

messages.OutreachMessage _buildMessage(
  LaunchRosterEntry entry, {
  required String playOptInLink,
}) {
  final row = <String, String>{
    'slot': entry.slot,
    'segment': entry.segment,
    'use_case': entry.useCase,
    'contact_channel': entry.contactChannel,
    'first_contact_date': '',
  };

  return messages
      .buildOutreachMessages(
        [row],
        count: 1,
        language: entry.language,
        playOptInLink: playOptInLink,
      )
      .single;
}

String _sendAction(LaunchRosterEntry entry, String body) {
  if (!entry.contactChannel.toLowerCase().contains('whatsapp')) {
    return 'Copy into ${entry.contactChannel}';
  }

  final query = Uri(queryParameters: {'text': body}).query;
  return '[Open WhatsApp draft](https://wa.me/?$query)';
}

String _renderChecklist(
  List<LaunchRosterEntry> entries, {
  required int testerCount,
  required int includedExistingEmails,
  DateTime? today,
}) {
  final date = today == null
      ? DateTime.now().toIso8601String().split('T').first
      : today.toIso8601String().split('T').first;

  final buffer = StringBuffer()
    ..writeln('# Rihla First-100 Launch Packet Checklist')
    ..writeln()
    ..writeln('Date: $date')
    ..writeln()
    ..writeln('## Batch')
    ..writeln()
    ..writeln('- Champions: ${entries.length}')
    ..writeln('- Play tester emails: $testerCount')
    ..writeln('- Includes $includedExistingEmails already-active tester emails')
    ..writeln()
    ..writeln('## Steps')
    ..writeln()
    ..writeln('1. Upload `play-testers.csv` to the Play Console tester list.')
    ..writeln('2. Confirm the Play tester opt-in link still opens.')
    ..writeln('3. Use `send-sheet.md` to send one champion message at a time.')
    ..writeln('4. Set `tester_added=yes` after Play access is confirmed.')
    ..writeln('5. Set `first_contact_date=$date` after each message is sent.')
    ..writeln('6. Set next-day follow-up dates in the private tracker.')
    ..writeln('7. Run `dart tool/first_100_summary.dart --today=$date`.')
    ..writeln();

  return buffer.toString();
}

String _markdownCell(String value) => value.replaceAll('|', r'\|');

String _csvCell(String value) {
  if (!value.contains(',') && !value.contains('"') && !value.contains('\n')) {
    return value;
  }
  return '"${value.replaceAll('"', '""')}"';
}

List<List<String>> _parseCsv(String source) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < source.length; i += 1) {
    final char = source[i];

    if (inQuotes) {
      if (char == '"') {
        final nextIndex = i + 1;
        if (nextIndex < source.length && source[nextIndex] == '"') {
          cell.write('"');
          i += 1;
        } else {
          inQuotes = false;
        }
      } else {
        cell.write(char);
      }
      continue;
    }

    if (char == '"') {
      inQuotes = true;
    } else if (char == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (char == '\n') {
      row.add(cell.toString());
      rows.add(row);
      row = <String>[];
      cell.clear();
    } else if (char != '\r') {
      cell.write(char);
    }
  }

  if (inQuotes) {
    throw const FormatException('unterminated quoted CSV cell');
  }

  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }

  return rows;
}
