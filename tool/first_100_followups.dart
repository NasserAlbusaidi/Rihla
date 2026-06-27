// tool/first_100_followups.dart
//
// Generates privacy-safe follow-up prompts from the first-100 tracker.
// The output uses slot numbers and campaign context, but does not print
// champion names or tester emails.
//
// Run via:
//   dart tool/first_100_followups.dart --today=2026-06-27
//   dart tool/first_100_followups.dart path/to/tracker.csv --today=2026-06-27

import 'dart:io';

import 'first_100_summary.dart' as first100;

const defaultFollowUpCount = 10;

class FollowUpPrompt {
  FollowUpPrompt({
    required this.slot,
    required this.segment,
    required this.useCase,
    required this.channel,
    required this.stage,
    required this.body,
  });

  final String slot;
  final String segment;
  final String useCase;
  final String channel;
  final String stage;
  final String body;
}

List<FollowUpPrompt> buildFollowUpPrompts(
  List<Map<String, String>> rows, {
  required DateTime today,
  int count = defaultFollowUpCount,
}) {
  return rows
      .where((row) => _field(row, 'champion').isNotEmpty)
      .where((row) => !_isYes(row['activated_group']))
      .where((row) => _isFollowUpDue(_field(row, 'follow_up_date'), today))
      .take(count)
      .map(_buildPrompt)
      .toList(growable: false);
}

String renderFollowUpPrompts(
  List<FollowUpPrompt> prompts, {
  required DateTime today,
}) {
  if (prompts.isEmpty) {
    return 'No due first-100 follow-ups found.\n';
  }

  final buffer = StringBuffer()
    ..writeln('# Rihla First-100 Follow-Up Prompts')
    ..writeln()
    ..writeln('Date: ${_dateLabel(today)}')
    ..writeln();

  for (final prompt in prompts) {
    buffer
      ..writeln('## Slot ${prompt.slot} - ${prompt.stage}')
      ..writeln()
      ..writeln('- Segment: ${prompt.segment}')
      ..writeln('- Use case: ${prompt.useCase}')
      ..writeln('- Channel: ${prompt.channel}')
      ..writeln()
      ..writeln('```text')
      ..writeln(prompt.body)
      ..writeln('```')
      ..writeln();
  }

  return buffer.toString();
}

Future<void> main(List<String> args) async {
  var trackerPath = first100.defaultTrackerPath;
  var today = DateTime.now();
  var count = defaultFollowUpCount;

  for (final arg in args) {
    if (arg.startsWith('--today=')) {
      today = _parseDate(arg.substring('--today='.length));
    } else if (arg.startsWith('--count=')) {
      count = int.parse(arg.substring('--count='.length));
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
  final prompts = buildFollowUpPrompts(rows, today: today, count: count);
  stdout.write(renderFollowUpPrompts(prompts, today: today));
}

FollowUpPrompt _buildPrompt(Map<String, String> row) {
  final slot = _field(row, 'slot');
  final segment = _field(row, 'segment');
  final useCase = _field(row, 'use_case');
  final channel = _field(row, 'contact_channel');

  if (!_isYes(row['tester_added'])) {
    return FollowUpPrompt(
      slot: slot,
      segment: segment,
      useCase: useCase,
      channel: channel,
      stage: 'Tester access',
      body:
          'Confirm the Google Play account for slot $slot and add it to the '
          'alpha tester list. After access is confirmed, send the opt-in link '
          'and ask them to install today.',
    );
  }

  if (_intField(row, 'installs_reported') == 0) {
    return FollowUpPrompt(
      slot: slot,
      segment: segment,
      useCase: useCase,
      channel: channel,
      stage: 'Install',
      body:
          'Open the tester opt-in link, join the test, then install Rihla from '
          'Google Play. Reply once installed so the next ask is one real group.',
    );
  }

  if (!_isYes(row['group_created'])) {
    return FollowUpPrompt(
      slot: slot,
      segment: segment,
      useCase: useCase,
      channel: channel,
      stage: 'Create the group',
      body:
          'Now create the Rihla group for the real $useCase use case. Keep it '
          'simple: create group, add the first event if needed, and send the '
          'WhatsApp invite.',
    );
  }

  if (!_isYes(row['invite_sent'])) {
    return FollowUpPrompt(
      slot: slot,
      segment: segment,
      useCase: useCase,
      channel: channel,
      stage: 'Send invite',
      body:
          'Send the WhatsApp invite now. The activation test is whether people '
          'can join the group from the invite, not only whether the app opened.',
    );
  }

  if (_intField(row, 'joined_count') == 0) {
    return FollowUpPrompt(
      slot: slot,
      segment: segment,
      useCase: useCase,
      channel: channel,
      stage: 'Help invitees join',
      body:
          'Check whether anyone joined from the invite. If not, ask them to tap '
          'the WhatsApp invite again after installing so the group code opens.',
    );
  }

  if (_intField(row, 'expenses_count') + _intField(row, 'settlements_count') ==
      0) {
    return FollowUpPrompt(
      slot: slot,
      segment: segment,
      useCase: useCase,
      channel: channel,
      stage: 'First expense',
      body:
          'Ask them to add one real expense now while it is fresh. The goal is '
          'one real shared bill, then checking who owes who.',
    );
  }

  return FollowUpPrompt(
    slot: slot,
    segment: segment,
    useCase: useCase,
    channel: channel,
    stage: 'Feedback',
    body:
        'Ask what was confusing or slow before the first real shared-expense '
        'action. Record the exact blocker in the tracker.',
  );
}

String _field(Map<String, String> row, String field, {String fallback = ''}) {
  final value = row[field]?.trim();
  return value == null || value.isEmpty ? fallback : value;
}

bool _isYes(String? value) => (value ?? '').trim().toLowerCase() == 'yes';

int _intField(Map<String, String> row, String field) {
  return int.tryParse(_field(row, field, fallback: '0')) ?? 0;
}

bool _isFollowUpDue(String value, DateTime today) {
  if (value.isEmpty) {
    return false;
  }
  final dueDate = DateTime.tryParse(value);
  if (dueDate == null) {
    return false;
  }
  final todayDate = DateTime(today.year, today.month, today.day);
  final dueDateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);
  return !dueDateOnly.isAfter(todayDate);
}

DateTime _parseDate(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('invalid date: $value');
  }
  return parsed;
}

String _dateLabel(DateTime today) => DateTime(
  today.year,
  today.month,
  today.day,
).toIso8601String().split('T').first;
