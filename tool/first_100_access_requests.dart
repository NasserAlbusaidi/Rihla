// tool/first_100_access_requests.dart
//
// Builds a private access-request packet for named first-100 champions who
// still need to send their Google Play account email. Terminal output reports
// only counts and slot numbers; generated files are private and may include
// champion names.
//
// Run via:
//   dart tool/first_100_access_requests.dart \
//     ~/Desktop/rihla-first-10-roster.csv \
//     --output=/tmp/rihla-first-10-access-requests.md

import 'dart:io';

import 'first_100_launch_packet.dart' as launch_packet;

class AccessRequestPacket {
  AccessRequestPacket({required this.markdown, required this.slots});

  final String markdown;
  final List<String> slots;
}

class AccessRequestEntry {
  AccessRequestEntry({
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

AccessRequestPacket buildAccessRequestPacket(String source, {int? count}) {
  final rows = _parseCsv(source);
  if (rows.isEmpty) {
    throw const FormatException('launch roster CSV is empty');
  }

  final header = rows.first.map((cell) => cell.trim()).toList(growable: false);
  final missingColumns = launch_packet.requiredLaunchRosterColumns.where(
    (column) => !header.contains(column),
  );
  if (missingColumns.isNotEmpty) {
    throw FormatException(
      'launch roster missing columns: ${missingColumns.join(', ')}',
    );
  }

  final entries = <AccessRequestEntry>[];
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

    if (champion.isEmpty || email.isNotEmpty) {
      continue;
    }
    if (slot.isEmpty) {
      throw const FormatException('access request row missing slot');
    }
    if (language != 'en' && language != 'ar') {
      throw ArgumentError.value(language, 'language', 'Use en or ar.');
    }
    if (segment.isEmpty || useCase.isEmpty || contactChannel.isEmpty) {
      throw FormatException(
        'access request slot $slot missing outreach context',
      );
    }

    entries.add(
      AccessRequestEntry(
        slot: slot,
        champion: champion,
        language: language,
        segment: segment,
        useCase: useCase,
        contactChannel: contactChannel,
      ),
    );
  }

  final selected = count == null
      ? entries
      : entries.take(count).toList(growable: false);

  return AccessRequestPacket(
    markdown: _renderMarkdown(selected),
    slots: [for (final entry in selected) entry.slot],
  );
}

String renderSummary(AccessRequestPacket packet) {
  final buffer = StringBuffer()
    ..writeln('# Rihla First-100 Access Request Summary')
    ..writeln()
    ..writeln('| Metric | Value |')
    ..writeln('|---|---:|')
    ..writeln('| Access requests | ${packet.slots.length} |')
    ..writeln()
    ..writeln(
      'Slots needing Play email: '
      '${packet.slots.isEmpty ? 'none' : packet.slots.join(', ')}',
    )
    ..writeln();

  if (packet.slots.isEmpty) {
    buffer.writeln('Fill champion names before requesting Play emails.');
  } else {
    buffer.writeln(
      'Send the private access request file, fill `google_play_email`, then run `dart tool/first_100_roster_check.dart <private-roster.csv>`.',
    );
  }

  return buffer.toString();
}

Future<void> main(List<String> args) async {
  String? inputPath;
  String? outputPath;
  int? count;

  for (final arg in args) {
    if (arg.startsWith('--output=')) {
      outputPath = arg.substring('--output='.length);
    } else if (arg.startsWith('--count=')) {
      count = int.parse(arg.substring('--count='.length));
    } else if (!arg.startsWith('--') && inputPath == null) {
      inputPath = arg;
    }
  }

  if (inputPath == null || outputPath == null) {
    stderr.writeln(
      'Usage: dart tool/first_100_access_requests.dart '
      '<private-roster.csv> --output=<private-access-requests.md> '
      '[--count=10]',
    );
    exit(64);
  }

  final packet = buildAccessRequestPacket(
    await File(inputPath).readAsString(),
    count: count,
  );
  await File(outputPath).writeAsString(packet.markdown);
  stdout.write(renderSummary(packet));
  if (packet.slots.isEmpty) {
    exit(65);
  }
}

String _renderMarkdown(List<AccessRequestEntry> entries) {
  final buffer = StringBuffer()
    ..writeln('# Rihla First-100 Access Requests')
    ..writeln();

  if (entries.isEmpty) {
    buffer
      ..writeln('No named champions are missing Play emails.')
      ..writeln()
      ..writeln(
        'Fill champion names before requesting Play emails, or generate the launch packet if emails are already filled.',
      );
    return buffer.toString();
  }

  for (final entry in entries) {
    buffer
      ..writeln('## Slot ${entry.slot} - ${entry.champion}')
      ..writeln()
      ..writeln('Channel: ${entry.contactChannel}')
      ..writeln('Segment: ${entry.segment}')
      ..writeln('Use case: ${entry.useCase}')
      ..writeln()
      ..writeln(
        entry.language == 'ar'
            ? _arabicAccessMessage(entry.useCase)
            : _englishAccessMessage(entry.useCase),
      )
      ..writeln();
  }

  return buffer.toString();
}

String _englishAccessMessage(String useCase) => '''
Quick access step first: which Google account do you use in the Play Store?

Rihla is still on Android alpha, so I need to add that Google account before the install link works.

After I add it, I will send the tester link. Best test for you: $useCase.''';

String _arabicAccessMessage(String useCase) => '''
أولًا أحتاج خطوة الوصول: ما حساب Google الذي تستخدمه في Google Play؟

Rihla لا يزال في Android alpha، لذلك أحتاج أضيف هذا الحساب قبل أن يعمل رابط التثبيت.

بعد إضافتك سأرسل رابط المختبرين. أفضل تجربة لك: $useCase.''';

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
