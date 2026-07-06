// tool/first_100_roster_check.dart
//
// Checks a private first-100 launch roster before Play upload or message
// generation. Output is privacy-safe: it reports slot numbers and issue types,
// never champion names or tester emails.
//
// Run via:
//   dart tool/first_100_roster_check.dart ~/Desktop/rihla-first-10-roster.csv

import 'dart:io';

import 'first_100_launch_packet.dart' as launch_packet;

class RosterCheckResult {
  RosterCheckResult({
    required this.totalRows,
    required this.readyRows,
    required this.issueRows,
  });

  final int totalRows;
  final int readyRows;
  final List<RosterIssueRow> issueRows;

  bool get isReady => totalRows > 0 && issueRows.isEmpty;
}

class RosterIssueRow {
  RosterIssueRow({required this.slot, required this.issues});

  final String slot;
  final List<String> issues;
}

RosterCheckResult checkLaunchRoster(String source) {
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

  final dataRows = rows
      .skip(1)
      .where((row) => row.any((cell) => cell.trim().isNotEmpty))
      .toList(growable: false);
  final seenEmails = <String>{};
  final issueRows = <RosterIssueRow>[];
  var readyRows = 0;

  for (final row in dataRows) {
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
    final normalizedEmail = email.toLowerCase();
    final issues = <String>[];

    if (slot.isEmpty) {
      issues.add('missing slot');
    }
    if (champion.isEmpty) {
      issues.add('missing champion');
    }
    if (email.isEmpty) {
      issues.add('missing google_play_email');
    } else if (!_looksLikeEmail(email)) {
      issues.add('invalid google_play_email');
    } else if (!seenEmails.add(normalizedEmail)) {
      issues.add('duplicate google_play_email');
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

    if (issues.isEmpty) {
      readyRows += 1;
    } else {
      issueRows.add(
        RosterIssueRow(
          slot: slot.isEmpty ? '(missing slot)' : slot,
          issues: issues,
        ),
      );
    }
  }

  return RosterCheckResult(
    totalRows: dataRows.length,
    readyRows: readyRows,
    issueRows: issueRows,
  );
}

String renderMarkdown(RosterCheckResult result) {
  final buffer = StringBuffer()
    ..writeln('# Rihla First-100 Roster Check')
    ..writeln()
    ..writeln('| Metric | Value |')
    ..writeln('|---|---:|')
    ..writeln('| Total rows | ${result.totalRows} |')
    ..writeln('| Ready rows | ${result.readyRows} |')
    ..writeln('| Rows with issues | ${result.issueRows.length} |')
    ..writeln();

  if (result.isReady) {
    buffer
      ..writeln('Roster is ready for launch packet generation.')
      ..writeln()
      ..writeln(
        'Next command: `dart tool/first_100_launch_packet.dart <private-roster.csv> --play-opt-in-link="<https-url>" --output-dir=<private-output-dir>`',
      );
    return buffer.toString();
  }

  buffer
    ..writeln('## Issues')
    ..writeln()
    ..writeln('| Slot | Issues |')
    ..writeln('|---:|---|');

  for (final row in result.issueRows) {
    buffer.writeln('| ${row.slot} | ${row.issues.join(', ')} |');
  }

  buffer
    ..writeln()
    ..writeln(
      'Fix these rows before generating a Play upload or outreach packet.',
    );
  return buffer.toString();
}

Future<void> main(List<String> args) async {
  if (args.length != 1 || args.first.startsWith('--')) {
    stderr.writeln(
      'Usage: dart tool/first_100_roster_check.dart <private-roster.csv>',
    );
    exit(64);
  }

  final source = await File(args.single).readAsString();
  final result = checkLaunchRoster(source);
  stdout.write(renderMarkdown(result));
  if (!result.isReady) {
    exit(65);
  }
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

bool _looksLikeEmail(String value) {
  final normalized = value.trim();
  return RegExp(r'^[^@\s,]+@[^@\s,]+\.[^@\s,]+$').hasMatch(normalized);
}
