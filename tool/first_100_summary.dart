// tool/first_100_summary.dart
//
// Summarizes docs/marketing/first-100-cohort-tracker.csv without printing
// private champion names or tester emails.
//
// Run via:
//   dart tool/first_100_summary.dart
//   dart tool/first_100_summary.dart path/to/tracker.csv --today=2026-06-27

import 'dart:io';

const defaultTrackerPath = 'docs/marketing/first-100-cohort-tracker.csv';

const requiredColumns = [
  'slot',
  'champion',
  'segment',
  'use_case',
  'contact_channel',
  'tester_added',
  'first_contact_date',
  'follow_up_date',
  'group_created',
  'invite_sent',
  'installs_reported',
  'joined_count',
  'expenses_count',
  'settlements_count',
  'activated_group',
  'top_blocker',
  'feedback',
  'next_action',
];

class TrackerSummary {
  TrackerSummary({
    required this.totalSlots,
    required this.namedChampions,
    required this.contactedSlots,
    required this.testerAddedSlots,
    required this.installedSlots,
    required this.groupsCreatedSlots,
    required this.invitesSentSlots,
    required this.joinedSlots,
    required this.activatedGroups,
    required this.feedbackNotes,
    required this.installsReported,
    required this.joinedUsers,
    required this.expenses,
    required this.settlements,
    required this.followUpsDue,
    required this.bySegment,
    required this.blockers,
    required this.nextSlots,
    required this.nextAction,
  });

  final int totalSlots;
  final int namedChampions;
  final int contactedSlots;
  final int testerAddedSlots;
  final int installedSlots;
  final int groupsCreatedSlots;
  final int invitesSentSlots;
  final int joinedSlots;
  final int activatedGroups;
  final int feedbackNotes;
  final int installsReported;
  final int joinedUsers;
  final int expenses;
  final int settlements;
  final int followUpsDue;
  final Map<String, SegmentSummary> bySegment;
  final Map<String, int> blockers;
  final List<NextSlot> nextSlots;
  final String nextAction;

  int get realActions => expenses + settlements;

  double get contactedToTester =>
      contactedSlots == 0 ? 0 : testerAddedSlots / contactedSlots;
  double get testerToInstalled =>
      testerAddedSlots == 0 ? 0 : installedSlots / testerAddedSlots;
  double get installedToGroup =>
      installedSlots == 0 ? 0 : groupsCreatedSlots / installedSlots;
  double get inviteToJoined =>
      invitesSentSlots == 0 ? 0 : joinedSlots / invitesSentSlots;
  double get joinedToExpense =>
      joinedSlots == 0 ? 0 : _rowsWithRealAction / joinedSlots;

  int get _rowsWithRealAction => bySegment.values.fold<int>(
    0,
    (total, segment) => total + segment.rowsWithRealAction,
  );
}

class SegmentSummary {
  SegmentSummary();

  int slots = 0;
  int named = 0;
  int contacted = 0;
  int testerAdded = 0;
  int installed = 0;
  int activatedGroups = 0;
  int rowsWithRealAction = 0;
}

class NextSlot {
  NextSlot({
    required this.slot,
    required this.segment,
    required this.useCase,
    required this.channel,
    required this.nextAction,
  });

  final String slot;
  final String segment;
  final String useCase;
  final String channel;
  final String nextAction;
}

List<Map<String, String>> parseTrackerCsv(String source) {
  final rows = _parseCsv(source);
  if (rows.isEmpty) {
    throw const FormatException('tracker CSV is empty');
  }

  final header = rows.first;
  final missing = requiredColumns.where((column) => !header.contains(column));
  if (missing.isNotEmpty) {
    throw FormatException('tracker CSV missing columns: ${missing.join(', ')}');
  }

  return rows
      .skip(1)
      .where((row) => row.any((cell) => cell.trim().isNotEmpty))
      .map((row) {
        final record = <String, String>{};
        for (var i = 0; i < header.length; i += 1) {
          record[header[i]] = i < row.length ? row[i].trim() : '';
        }
        return record;
      })
      .toList(growable: false);
}

TrackerSummary summarizeTracker(
  List<Map<String, String>> rows, {
  DateTime? today,
}) {
  final bySegment = <String, SegmentSummary>{};
  final blockers = <String, int>{};
  final nextSlots = <NextSlot>[];

  var namedChampions = 0;
  var contactedSlots = 0;
  var testerAddedSlots = 0;
  var installedSlots = 0;
  var groupsCreatedSlots = 0;
  var invitesSentSlots = 0;
  var joinedSlots = 0;
  var activatedGroups = 0;
  var feedbackNotes = 0;
  var installsReported = 0;
  var joinedUsers = 0;
  var expenses = 0;
  var settlements = 0;
  var followUpsDue = 0;

  for (final row in rows) {
    final segmentName = _field(row, 'segment', fallback: 'Unsegmented');
    final segment = bySegment.putIfAbsent(segmentName, SegmentSummary.new);
    segment.slots += 1;

    final championNamed = _field(row, 'champion').isNotEmpty;
    final contacted = _field(row, 'first_contact_date').isNotEmpty;
    final testerAdded = _isYes(row['tester_added']);
    final groupCreated = _isYes(row['group_created']);
    final inviteSent = _isYes(row['invite_sent']);
    final installedCount = _intField(row, 'installs_reported');
    final joinedCount = _intField(row, 'joined_count');
    final expenseCount = _intField(row, 'expenses_count');
    final settlementCount = _intField(row, 'settlements_count');
    final activated = _isYes(row['activated_group']);
    final hasFeedback = _field(row, 'feedback').isNotEmpty;
    final hasRealAction = expenseCount + settlementCount > 0;

    if (championNamed) {
      namedChampions += 1;
      segment.named += 1;
    } else if (nextSlots.length < 10) {
      nextSlots.add(
        NextSlot(
          slot: _field(row, 'slot'),
          segment: segmentName,
          useCase: _field(row, 'use_case'),
          channel: _field(row, 'contact_channel'),
          nextAction: _field(row, 'next_action'),
        ),
      );
    }
    if (contacted) {
      contactedSlots += 1;
      segment.contacted += 1;
    }
    if (testerAdded) {
      testerAddedSlots += 1;
      segment.testerAdded += 1;
    }
    if (installedCount > 0) {
      installedSlots += 1;
      segment.installed += 1;
    }
    if (groupCreated) {
      groupsCreatedSlots += 1;
    }
    if (inviteSent) {
      invitesSentSlots += 1;
    }
    if (joinedCount > 0) {
      joinedSlots += 1;
    }
    if (activated) {
      activatedGroups += 1;
      segment.activatedGroups += 1;
    }
    if (hasFeedback) {
      feedbackNotes += 1;
    }
    if (joinedCount > 0 && hasRealAction) {
      segment.rowsWithRealAction += 1;
    }

    installsReported += installedCount;
    joinedUsers += joinedCount;
    expenses += expenseCount;
    settlements += settlementCount;

    final blocker = _field(row, 'top_blocker');
    if (blocker.isNotEmpty) {
      blockers[blocker] = (blockers[blocker] ?? 0) + 1;
    }

    if (today != null &&
        _isFollowUpDue(_field(row, 'follow_up_date'), today) &&
        !activated) {
      followUpsDue += 1;
    }
  }

  final summary = TrackerSummary(
    totalSlots: rows.length,
    namedChampions: namedChampions,
    contactedSlots: contactedSlots,
    testerAddedSlots: testerAddedSlots,
    installedSlots: installedSlots,
    groupsCreatedSlots: groupsCreatedSlots,
    invitesSentSlots: invitesSentSlots,
    joinedSlots: joinedSlots,
    activatedGroups: activatedGroups,
    feedbackNotes: feedbackNotes,
    installsReported: installsReported,
    joinedUsers: joinedUsers,
    expenses: expenses,
    settlements: settlements,
    followUpsDue: followUpsDue,
    bySegment: bySegment,
    blockers: blockers,
    nextSlots: nextSlots,
    nextAction: '',
  );

  return TrackerSummary(
    totalSlots: summary.totalSlots,
    namedChampions: summary.namedChampions,
    contactedSlots: summary.contactedSlots,
    testerAddedSlots: summary.testerAddedSlots,
    installedSlots: summary.installedSlots,
    groupsCreatedSlots: summary.groupsCreatedSlots,
    invitesSentSlots: summary.invitesSentSlots,
    joinedSlots: summary.joinedSlots,
    activatedGroups: summary.activatedGroups,
    feedbackNotes: summary.feedbackNotes,
    installsReported: summary.installsReported,
    joinedUsers: summary.joinedUsers,
    expenses: summary.expenses,
    settlements: summary.settlements,
    followUpsDue: summary.followUpsDue,
    bySegment: summary.bySegment,
    blockers: summary.blockers,
    nextSlots: summary.nextSlots,
    nextAction: _recommendNextAction(summary),
  );
}

String renderMarkdown(TrackerSummary summary, {DateTime? today}) {
  final buffer = StringBuffer()
    ..writeln('# Rihla First-100 Tracker Summary')
    ..writeln()
    ..writeln('Date: ${_dateLabel(today)}')
    ..writeln()
    ..writeln('## North-Star Progress')
    ..writeln()
    ..writeln('| Metric | Current | Target |')
    ..writeln('|---|---:|---:|')
    ..writeln('| Named champions | ${summary.namedChampions} | 40 |')
    ..writeln('| Total installs reported | ${summary.installsReported} | 100 |')
    ..writeln('| Joined users reported | ${summary.joinedUsers} | 60 |')
    ..writeln('| Activated groups | ${summary.activatedGroups} | 20 |')
    ..writeln('| Real expenses/settlements | ${summary.realActions} | 50 |')
    ..writeln('| Written feedback notes | ${summary.feedbackNotes} | 10 |')
    ..writeln()
    ..writeln('## Champion Funnel')
    ..writeln()
    ..writeln('| Step | Slots | Rate | Healthy threshold |')
    ..writeln('|---|---:|---:|---:|')
    ..writeln(
      '| Contacted -> tester added | ${summary.contactedSlots} -> ${summary.testerAddedSlots} | ${_percent(summary.contactedToTester)} | 70% |',
    )
    ..writeln(
      '| Tester added -> installed | ${summary.testerAddedSlots} -> ${summary.installedSlots} | ${_percent(summary.testerToInstalled)} | 75% |',
    )
    ..writeln(
      '| Installed -> group created | ${summary.installedSlots} -> ${summary.groupsCreatedSlots} | ${_percent(summary.installedToGroup)} | 65% |',
    )
    ..writeln(
      '| Invite sent -> joined | ${summary.invitesSentSlots} -> ${summary.joinedSlots} | ${_percent(summary.inviteToJoined)} | 60% |',
    )
    ..writeln(
      '| Joined -> first real action | ${summary.joinedSlots} -> ${summary._rowsWithRealAction} | ${_percent(summary.joinedToExpense)} | 60% |',
    )
    ..writeln()
    ..writeln('## Segment Coverage')
    ..writeln()
    ..writeln(
      '| Segment | Slots | Named | Contacted | Tester-added | Installed | Activated groups |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|---:|');

  final segments = summary.bySegment.keys.toList()..sort();
  for (final name in segments) {
    final segment = summary.bySegment[name]!;
    buffer.writeln(
      '| $name | ${segment.slots} | ${segment.named} | ${segment.contacted} | ${segment.testerAdded} | ${segment.installed} | ${segment.activatedGroups} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Blockers')
    ..writeln();

  if (summary.blockers.isEmpty) {
    buffer.writeln('No blockers recorded yet.');
  } else {
    final blockers = summary.blockers.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in blockers) {
      buffer.writeln('- ${entry.key}: ${entry.value}');
    }
  }

  buffer
    ..writeln()
    ..writeln('## Next Empty Slots')
    ..writeln();

  if (summary.nextSlots.isEmpty) {
    buffer.writeln('No empty champion slots remain.');
  } else {
    buffer
      ..writeln('| Slot | Segment | Use case | Channel | Next action |')
      ..writeln('|---:|---|---|---|---|');
    for (final slot in summary.nextSlots) {
      buffer.writeln(
        '| ${slot.slot} | ${slot.segment} | ${slot.useCase} | ${slot.channel} | ${slot.nextAction} |',
      );
    }
  }

  buffer
    ..writeln()
    ..writeln('## Recommended Next Action')
    ..writeln()
    ..writeln(summary.nextAction);

  if (today != null) {
    buffer
      ..writeln()
      ..writeln('Follow-ups due today or earlier: ${summary.followUpsDue}');
  }

  return buffer.toString();
}

Future<void> main(List<String> args) async {
  var trackerPath = defaultTrackerPath;
  DateTime? today;

  for (final arg in args) {
    if (arg.startsWith('--today=')) {
      final raw = arg.substring('--today='.length);
      try {
        today = DateTime.parse(raw);
      } on FormatException {
        stderr.writeln(
          'Invalid --today value "$raw": expected an ISO-8601 date (YYYY-MM-DD).',
        );
        exit(64);
      }
    } else if (!arg.startsWith('--')) {
      trackerPath = arg;
    }
  }

  final source = await File(trackerPath).readAsString();
  final rows = parseTrackerCsv(source);
  final summary = summarizeTracker(rows, today: today);
  stdout.write(renderMarkdown(summary, today: today));
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

String _field(Map<String, String> row, String key, {String fallback = ''}) {
  final value = row[key]?.trim() ?? '';
  return value.isEmpty ? fallback : value;
}

bool _isYes(String? value) => value?.trim().toLowerCase() == 'yes';

int _intField(Map<String, String> row, String key) {
  final raw = _field(row, key);
  if (raw.isEmpty) {
    return 0;
  }
  return int.tryParse(raw) ?? 0;
}

bool _isFollowUpDue(String value, DateTime today) {
  if (value.isEmpty) {
    return false;
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return false;
  }
  final todayDate = DateTime(today.year, today.month, today.day);
  final parsedDate = DateTime(parsed.year, parsed.month, parsed.day);
  return !parsedDate.isAfter(todayDate);
}

String _recommendNextAction(TrackerSummary summary) {
  if (summary.namedChampions < 10) {
    return 'Fill the first 10 champion names, confirm Play access, and send the Day-1 messages.';
  }
  if (summary.contactedSlots < 20) {
    return 'Contact more named champions before spending more time on SEO or screenshots.';
  }
  if (summary.contactedSlots > 0 && summary.contactedToTester < 0.70) {
    return 'Pause broad outreach and fix Play tester access instructions.';
  }
  if (summary.testerAddedSlots > 0 && summary.testerToInstalled < 0.75) {
    return 'Focus on Play opt-in/install friction before recruiting more champions.';
  }
  if (summary.installedSlots > 0 && summary.installedToGroup < 0.65) {
    return 'Coach champions through create group -> invite -> first expense.';
  }
  if (summary.invitesSentSlots > 0 && summary.inviteToJoined < 0.60) {
    return 'Prioritize deferred invite capture (#368) before more landing-page polish.';
  }
  if (summary.joinedSlots > 0 && summary.joinedToExpense < 0.60) {
    return 'Prioritize first-expense activation and champion follow-up.';
  }
  return 'Keep recruiting champions and ask activated groups for warm intros.';
}

String _percent(double value) => '${(value * 100).round()}%';

String _dateLabel(DateTime? today) {
  if (today == null) {
    return 'not specified';
  }
  final year = today.year.toString().padLeft(4, '0');
  final month = today.month.toString().padLeft(2, '0');
  final day = today.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
