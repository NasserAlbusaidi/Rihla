// tool/export_play_tester_emails.dart
//
// Exports a private first-100 tester roster into the one-email-per-line CSV
// expected by Play Console tester list upload.
//
// Run via:
//   dart tool/export_play_tester_emails.dart ~/Desktop/rihla-first-100-play-testers.csv --output=/tmp/rihla-play-testers.csv

import 'dart:io';

const defaultEmailColumn = 'google_play_email';

class TesterEmailExport {
  TesterEmailExport({
    required this.emails,
    required this.skippedBlankRows,
    this.includedExistingEmails = 0,
  });

  final List<String> emails;
  final int skippedBlankRows;
  final int includedExistingEmails;
}

TesterEmailExport exportTesterEmailsFromCsv(
  String source, {
  String emailColumn = defaultEmailColumn,
  String? existingEmailsSource,
}) {
  final rows = _parseCsv(source);
  if (rows.isEmpty) {
    throw const FormatException('tester roster CSV is empty');
  }

  final header = rows.first.map((cell) => cell.trim()).toList(growable: false);
  final emailIndex = header.indexOf(emailColumn);
  if (emailIndex < 0) {
    throw FormatException('tester roster missing column: $emailColumn');
  }

  final emails = <String>[];
  final seen = <String>{};
  var includedExistingEmails = 0;
  var skippedBlankRows = 0;

  if (existingEmailsSource != null) {
    for (final email in _parseExistingEmails(existingEmailsSource)) {
      if (seen.add(email)) {
        emails.add(email);
        includedExistingEmails += 1;
      }
    }
  }

  for (final row in rows.skip(1)) {
    final raw = emailIndex < row.length ? row[emailIndex].trim() : '';
    if (raw.isEmpty) {
      skippedBlankRows += 1;
      continue;
    }

    final normalized = raw.toLowerCase();
    if (!_looksLikeEmail(normalized)) {
      throw FormatException('invalid tester email: $raw');
    }
    if (seen.add(normalized)) {
      emails.add(normalized);
    }
  }

  if (emails.isEmpty) {
    throw const FormatException('tester roster has no usable emails');
  }

  return TesterEmailExport(
    emails: emails,
    skippedBlankRows: skippedBlankRows,
    includedExistingEmails: includedExistingEmails,
  );
}

String renderPlayTesterCsv(TesterEmailExport export) {
  // Play's help page says each email address should be on its own line without
  // commas, and that UTF-8 with BOM is rejected. Dart's default writeAsString
  // writes plain UTF-8 without a BOM.
  return '${export.emails.join('\n')}\n';
}

Future<void> main(List<String> args) async {
  String? inputPath;
  String? outputPath;
  String? existingEmailsPath;
  var emailColumn = defaultEmailColumn;

  for (final arg in args) {
    if (arg.startsWith('--output=')) {
      outputPath = arg.substring('--output='.length);
    } else if (arg.startsWith('--include-existing=')) {
      existingEmailsPath = arg.substring('--include-existing='.length);
    } else if (arg.startsWith('--column=')) {
      emailColumn = arg.substring('--column='.length);
    } else if (!arg.startsWith('--')) {
      inputPath = arg;
    }
  }

  if (inputPath == null) {
    stderr.writeln(
      'Usage: dart tool/export_play_tester_emails.dart <private-roster.csv> '
      '[--output=/tmp/rihla-play-testers.csv] '
      '[--include-existing=/tmp/current-play-testers.csv] '
      '[--column=google_play_email]',
    );
    exit(64);
  }

  final source = await File(inputPath).readAsString();
  final existingEmailsSource = existingEmailsPath == null
      ? null
      : await File(existingEmailsPath).readAsString();
  final export = exportTesterEmailsFromCsv(
    source,
    emailColumn: emailColumn,
    existingEmailsSource: existingEmailsSource,
  );
  final rendered = renderPlayTesterCsv(export);

  if (outputPath == null) {
    stdout.write(rendered);
  } else {
    await File(outputPath).writeAsString(rendered);
    stderr.writeln(
      'Exported ${export.emails.length} tester emails to $outputPath '
      '(${export.includedExistingEmails} active existing included, '
      '${export.skippedBlankRows} blank rows skipped).',
    );
  }
}

List<String> _parseExistingEmails(String source) {
  final emails = <String>[];
  for (final line in source.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final normalized = trimmed.toLowerCase();
    if (!_looksLikeEmail(normalized)) {
      throw FormatException('invalid existing tester email: $trimmed');
    }
    emails.add(normalized);
  }
  return emails;
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

bool _looksLikeEmail(String value) =>
    RegExp(r'^[^@\s,]+@[^@\s,]+\.[^@\s,]+$').hasMatch(value);
