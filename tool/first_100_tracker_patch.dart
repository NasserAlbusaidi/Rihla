// tool/first_100_tracker_patch.dart
//
// Applies a private filled launch roster to a tracker CSV and writes a private
// tracker copy. The private roster may contain champion names and Play emails;
// generated terminal output reports only slot numbers and counts.
//
// Run via:
//   dart tool/first_100_tracker_patch.dart \
//     docs/marketing/first-100-cohort-tracker.csv \
//     ~/Desktop/rihla-first-10-roster.csv \
//     --today=2026-06-27 \
//     --mark-tester-added \
//     --mark-contacted \
//     --output="$HOME/Desktop/rihla-first-100-tracker.csv"

import 'dart:io';

import 'export_play_tester_emails.dart' as email_exporter;
import 'first_100_launch_packet.dart' as launch_packet;
import 'first_100_summary.dart' as first100;

class TrackerPatchResult {
  TrackerPatchResult({
    required this.trackerCsv,
    required this.updatedSlots,
    required this.markTesterAdded,
    required this.markContacted,
    required this.today,
  });

  final String trackerCsv;
  final List<String> updatedSlots;
  final bool markTesterAdded;
  final bool markContacted;
  final DateTime today;
}

TrackerPatchResult applyLaunchRosterToTracker(
  String trackerCsv,
  String rosterCsv, {
  required DateTime today,
  bool markTesterAdded = false,
  bool markContacted = false,
}) {
  final trackerRows = first100
      .parseTrackerCsv(trackerCsv)
      .map(Map<String, String>.from)
      .toList(growable: false);
  final rosterEntries = launch_packet.parseLaunchRoster(rosterCsv);

  // Validate email-looking roster values before patching, but never carry them
  // into the tracker output.
  email_exporter.exportTesterEmailsFromCsv(rosterCsv);

  final trackerBySlot = <String, Map<String, String>>{
    for (final row in trackerRows) row['slot'] ?? '': row,
  };
  final updatedSlots = <String>[];
  final contactDate = _dateLabel(today);
  final followUpDate = _dateLabel(today.add(const Duration(days: 1)));

  for (final entry in rosterEntries) {
    final row = trackerBySlot[entry.slot];
    if (row == null) {
      throw FormatException(
        'launch roster slot ${entry.slot} is not present in tracker',
      );
    }

    row['champion'] = entry.champion;
    row['segment'] = entry.segment;
    row['use_case'] = entry.useCase;
    row['contact_channel'] = entry.contactChannel;
    row['top_blocker'] = '';
    row['feedback'] = '';

    if (markTesterAdded) {
      row['tester_added'] = 'yes';
    }
    if (markContacted) {
      row['first_contact_date'] = contactDate;
      row['follow_up_date'] = followUpDate;
      row['next_action'] = 'follow up after first ask';
    } else {
      row['next_action'] = 'send first ask';
    }

    updatedSlots.add(entry.slot);
  }

  return TrackerPatchResult(
    trackerCsv: _renderTrackerCsv(trackerRows),
    updatedSlots: updatedSlots,
    markTesterAdded: markTesterAdded,
    markContacted: markContacted,
    today: today,
  );
}

String renderMarkdown(TrackerPatchResult result) {
  final buffer = StringBuffer()
    ..writeln('# Rihla First-100 Tracker Patch')
    ..writeln()
    ..writeln('| Metric | Value |')
    ..writeln('|---|---:|')
    ..writeln('| Updated slots | ${result.updatedSlots.length} |')
    ..writeln(
      '| Tester-added marked | ${result.markTesterAdded ? 'yes' : 'no'} |',
    )
    ..writeln('| Contacted marked | ${result.markContacted ? 'yes' : 'no'} |')
    ..writeln()
    ..writeln('Slots updated: ${result.updatedSlots.join(', ')}')
    ..writeln()
    ..writeln(
      'Review the private tracker copy, then run `dart tool/first_100_summary.dart <private-tracker.csv> --today=${_dateLabel(result.today)}`.',
    );

  return buffer.toString();
}

Future<void> main(List<String> args) async {
  String? trackerPath;
  String? rosterPath;
  String? outputPath;
  DateTime? today;
  var markTesterAdded = false;
  var markContacted = false;

  for (final arg in args) {
    if (arg.startsWith('--output=')) {
      outputPath = arg.substring('--output='.length);
    } else if (arg.startsWith('--today=')) {
      today = DateTime.parse(arg.substring('--today='.length));
    } else if (arg == '--mark-tester-added') {
      markTesterAdded = true;
    } else if (arg == '--mark-contacted') {
      markContacted = true;
    } else if (!arg.startsWith('--') && trackerPath == null) {
      trackerPath = arg;
    } else if (!arg.startsWith('--') && rosterPath == null) {
      rosterPath = arg;
    }
  }

  if (trackerPath == null || rosterPath == null || outputPath == null) {
    stderr.writeln(
      'Usage: dart tool/first_100_tracker_patch.dart <tracker.csv> '
      '<private-roster.csv> --output=<private-tracker.csv> '
      '[--today=YYYY-MM-DD] [--mark-tester-added] [--mark-contacted]',
    );
    exit(64);
  }

  final result = applyLaunchRosterToTracker(
    await File(trackerPath).readAsString(),
    await File(rosterPath).readAsString(),
    today: today ?? DateTime.now(),
    markTesterAdded: markTesterAdded,
    markContacted: markContacted,
  );

  await File(outputPath).writeAsString(result.trackerCsv);
  stdout.write(renderMarkdown(result));
}

String _renderTrackerCsv(List<Map<String, String>> rows) {
  final buffer = StringBuffer()..writeln(first100.requiredColumns.join(','));
  for (final row in rows) {
    buffer.writeln(
      first100.requiredColumns
          .map((column) => _csvCell(row[column] ?? ''))
          .join(','),
    );
  }
  return buffer.toString();
}

String _csvCell(String value) {
  if (!value.contains(',') && !value.contains('"') && !value.contains('\n')) {
    return value;
  }
  return '"${value.replaceAll('"', '""')}"';
}

String _dateLabel(DateTime date) => date.toIso8601String().split('T').first;
