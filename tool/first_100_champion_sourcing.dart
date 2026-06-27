// tool/first_100_champion_sourcing.dart
//
// Builds and checks a private first-10 champion sourcing worksheet before the
// Play email/access-request step. Terminal output reports only counts and slot
// numbers; private worksheet/roster files may include champion names.
//
// Run via:
//   dart tool/first_100_champion_sourcing.dart \
//     --write-template="$HOME/Desktop/rihla-first-10-candidates.csv"
//   dart tool/first_100_champion_sourcing.dart \
//     "$HOME/Desktop/rihla-first-10-candidates.csv" \
//     --write-roster="$HOME/Desktop/rihla-first-10-roster.csv"

import 'dart:io';

import 'first_100_launch_packet.dart' as launch_packet;
import 'first_100_summary.dart' as first100;

const requiredSourcingColumns = [
  'slot',
  'candidate',
  'relationship',
  'language',
  'segment',
  'use_case',
  'contact_channel',
  'android_likely',
  'group_size_estimate',
  'has_live_bill',
  'priority',
  'next_action',
  'notes',
];

class SourcingCheck {
  SourcingCheck({
    required this.candidateRows,
    required this.readySlots,
    required this.issueRows,
  });

  final int candidateRows;
  final List<String> readySlots;
  final List<SourcingIssueRow> issueRows;
}

class SourcingIssueRow {
  SourcingIssueRow({required this.slot, required this.issues});

  final String slot;
  final List<String> issues;
}

class _SourcingEntry {
  _SourcingEntry({
    required this.slot,
    required this.candidate,
    required this.language,
    required this.segment,
    required this.useCase,
    required this.contactChannel,
    required this.issues,
  });

  final String slot;
  final String candidate;
  final String language;
  final String segment;
  final String useCase;
  final String contactChannel;
  final List<String> issues;
}

String buildSourcingWorksheetTemplate(String trackerCsv, {int count = 10}) {
  final rows = first100.parseTrackerCsv(trackerCsv);
  final buffer = StringBuffer()..writeln(requiredSourcingColumns.join(','));

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
        'unknown',
        '',
        'unknown',
        '',
        'identify and ask champion',
        '',
      ].map(_csvCell).join(','),
    );
  }

  return buffer.toString();
}

Future<void> writeSourcingWorksheetTemplate(
  String trackerCsv,
  String outputPath, {
  int count = 10,
}) async {
  await File(
    outputPath,
  ).writeAsString(buildSourcingWorksheetTemplate(trackerCsv, count: count));
}

SourcingCheck checkSourcingWorksheet(String source) {
  final entries = _parseSourcingEntries(source);
  return SourcingCheck(
    candidateRows: entries.length,
    readySlots: [
      for (final entry in entries)
        if (entry.issues.isEmpty) entry.slot,
    ],
    issueRows: [
      for (final entry in entries)
        if (entry.issues.isNotEmpty)
          SourcingIssueRow(slot: entry.slot, issues: entry.issues),
    ],
  );
}

String buildLaunchRosterFromSourcingWorksheet(String source, {int? count}) {
  final readyEntries = _parseSourcingEntries(
    source,
  ).where((entry) => entry.issues.isEmpty);
  final selected = count == null
      ? readyEntries
      : readyEntries.take(count).toList(growable: false);

  final buffer = StringBuffer()
    ..writeln(launch_packet.requiredLaunchRosterColumns.join(','));
  for (final entry in selected) {
    buffer.writeln(
      [
        entry.slot,
        entry.candidate,
        '',
        entry.language,
        entry.segment,
        entry.useCase,
        entry.contactChannel,
      ].map(_csvCell).join(','),
    );
  }
  return buffer.toString();
}

String renderSummary(SourcingCheck result) {
  final buffer = StringBuffer()
    ..writeln('# Rihla First-100 Champion Sourcing Summary')
    ..writeln()
    ..writeln('| Metric | Value |')
    ..writeln('|---|---:|')
    ..writeln('| Candidate rows | ${result.candidateRows} |')
    ..writeln('| Ready for access request | ${result.readySlots.length} |')
    ..writeln('| Rows with issues | ${result.issueRows.length} |')
    ..writeln()
    ..writeln(
      'Ready slots: '
      '${result.readySlots.isEmpty ? 'none' : result.readySlots.join(', ')}',
    )
    ..writeln();

  if (result.issueRows.isNotEmpty) {
    buffer
      ..writeln('## Issues')
      ..writeln()
      ..writeln('| Slot | Issues |')
      ..writeln('|---:|---|');
    for (final issueRow in result.issueRows) {
      buffer.writeln('| ${issueRow.slot} | ${issueRow.issues.join(', ')} |');
    }
    buffer.writeln();
  }

  if (result.readySlots.isEmpty) {
    buffer.writeln(
      'Name warm candidates and confirm Android, group size, and a live shared bill before requesting Play emails.',
    );
  } else {
    buffer.writeln(
      'Write the private roster, run `dart tool/first_100_access_requests.dart <private-roster.csv>`, then fill Google Play emails as replies arrive.',
    );
  }

  return buffer.toString();
}

Future<void> main(List<String> args) async {
  String? inputPath;
  String? templateOutputPath;
  String? rosterOutputPath;
  var count = 10;

  for (final arg in args) {
    if (arg.startsWith('--write-template=')) {
      templateOutputPath = arg.substring('--write-template='.length);
    } else if (arg.startsWith('--write-roster=')) {
      rosterOutputPath = arg.substring('--write-roster='.length);
    } else if (arg.startsWith('--count=')) {
      count = int.parse(arg.substring('--count='.length));
    } else if (!arg.startsWith('--') && inputPath == null) {
      inputPath = arg;
    }
  }

  if (templateOutputPath != null) {
    final trackerPath = inputPath ?? first100.defaultTrackerPath;
    final trackerCsv = await File(trackerPath).readAsString();
    await writeSourcingWorksheetTemplate(
      trackerCsv,
      templateOutputPath,
      count: count,
    );
    stderr.writeln('Wrote champion sourcing worksheet to $templateOutputPath');
    return;
  }

  if (inputPath == null) {
    stderr.writeln(
      'Usage: dart tool/first_100_champion_sourcing.dart '
      '[tracker.csv] --write-template=<private-candidates.csv> '
      '[--count=10]\n'
      '   or: dart tool/first_100_champion_sourcing.dart '
      '<private-candidates.csv> [--write-roster=<private-roster.csv>] '
      '[--count=10]',
    );
    exit(64);
  }

  final source = await File(inputPath).readAsString();
  final result = checkSourcingWorksheet(source);
  if (rosterOutputPath != null) {
    await File(rosterOutputPath).writeAsString(
      buildLaunchRosterFromSourcingWorksheet(source, count: count),
    );
  }

  stdout.write(renderSummary(result));
  if (result.readySlots.isEmpty) {
    exit(65);
  }
}

List<_SourcingEntry> _parseSourcingEntries(String source) {
  final rows = _parseCsv(source);
  if (rows.isEmpty) {
    throw const FormatException('champion sourcing CSV is empty');
  }

  final header = rows.first.map((cell) => cell.trim()).toList(growable: false);
  final missingColumns = requiredSourcingColumns.where(
    (column) => !header.contains(column),
  );
  if (missingColumns.isNotEmpty) {
    throw FormatException(
      'champion sourcing CSV missing columns: ${missingColumns.join(', ')}',
    );
  }

  final entries = <_SourcingEntry>[];
  for (final row in rows.skip(1)) {
    if (row.every((cell) => cell.trim().isEmpty)) {
      continue;
    }

    String field(String column) {
      final index = header.indexOf(column);
      return index < row.length ? row[index].trim() : '';
    }

    final slot = field('slot');
    final candidate = field('candidate');
    final relationship = field('relationship');
    final language = field('language').toLowerCase();
    final segment = field('segment');
    final useCase = field('use_case');
    final contactChannel = field('contact_channel');
    final androidLikely = field('android_likely').toLowerCase();
    final groupSizeEstimate = field('group_size_estimate');
    final hasLiveBill = field('has_live_bill').toLowerCase();
    final priority = field('priority');
    final issues = <String>[];

    if (slot.isEmpty) {
      issues.add('missing slot');
    }
    if (candidate.isEmpty) {
      issues.add('missing candidate');
    }
    if (relationship.isEmpty) {
      issues.add('missing relationship');
    }
    if (language != 'en' && language != 'ar') {
      issues.add('unsupported language');
    }
    if (segment.isEmpty) {
      issues.add('missing segment');
    }
    if (useCase.isEmpty) {
      issues.add('missing use_case');
    }
    if (contactChannel.isEmpty) {
      issues.add('missing contact_channel');
    }
    if (androidLikely != 'yes') {
      issues.add('android_likely is not yes');
    }
    if (groupSizeEstimate.isEmpty) {
      issues.add('missing group_size_estimate');
    } else {
      final parsedGroupSize = int.tryParse(groupSizeEstimate);
      if (parsedGroupSize == null) {
        issues.add('invalid group_size_estimate');
      } else if (parsedGroupSize < 2) {
        issues.add('group_size_estimate below 2');
      }
    }
    if (hasLiveBill != 'yes') {
      issues.add('has_live_bill is not yes');
    }
    if (!_isSupportedPriority(priority)) {
      issues.add(
        priority.isEmpty ? 'missing priority' : 'unsupported priority',
      );
    }

    entries.add(
      _SourcingEntry(
        slot: slot.isEmpty ? 'unknown' : slot,
        candidate: candidate,
        language: language,
        segment: segment,
        useCase: useCase,
        contactChannel: contactChannel,
        issues: issues,
      ),
    );
  }

  return entries;
}

bool _isSupportedPriority(String value) =>
    value == '1' || value == '2' || value == '3';

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

String _csvCell(String value) {
  if (!value.contains(',') &&
      !value.contains('"') &&
      !value.contains('\n') &&
      !value.contains('\r')) {
    return value;
  }
  return '"${value.replaceAll('"', '""')}"';
}
