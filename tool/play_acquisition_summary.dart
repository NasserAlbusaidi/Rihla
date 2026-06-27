// tool/play_acquisition_summary.dart
//
// Summarizes a private weekly Play acquisition log and ties listing decisions
// back to the first-100 tracker. Keep the input CSV outside git.
//
// Run via:
//   dart tool/play_acquisition_summary.dart ~/Desktop/rihla-play-acquisition-log.csv
//   dart tool/play_acquisition_summary.dart ~/Desktop/rihla-play-acquisition-log.csv docs/marketing/first-100-cohort-tracker.csv
//   dart tool/play_acquisition_summary.dart --write-template=~/Desktop/rihla-play-acquisition-log.csv

import 'dart:io';

import 'first_100_summary.dart' as first100;

const requiredAcquisitionColumns = [
  'week_start',
  'week_end',
  'store_listing_visitors',
  'first_time_installers',
  'tracker_installs',
  'activated_groups',
  'variant',
  'decision',
  'notes',
];

const optionalAcquisitionColumns = [
  'top_country',
  'top_language',
  'search_terms',
];

class PlayAcquisitionWeek {
  PlayAcquisitionWeek({
    required this.weekStart,
    required this.weekEnd,
    required this.storeListingVisitors,
    required this.firstTimeInstallers,
    required this.trackerInstalls,
    required this.activatedGroups,
    required this.variant,
    required this.decision,
    required this.notes,
    required this.topCountry,
    required this.topLanguage,
    required this.searchTerms,
  });

  final String weekStart;
  final String weekEnd;
  final int storeListingVisitors;
  final int firstTimeInstallers;
  final int trackerInstalls;
  final int activatedGroups;
  final String variant;
  final String decision;
  final String notes;
  final String topCountry;
  final String topLanguage;
  final String searchTerms;

  double get conversionRate => storeListingVisitors == 0
      ? 0
      : firstTimeInstallers / storeListingVisitors;
}

class PlayAcquisitionSummary {
  PlayAcquisitionSummary({
    required this.weeks,
    required this.trackerSummary,
    required this.recommendedNextAction,
  });

  final List<PlayAcquisitionWeek> weeks;
  final first100.TrackerSummary? trackerSummary;
  final String recommendedNextAction;

  PlayAcquisitionWeek? get latest => weeks.isEmpty ? null : weeks.last;

  bool get hasExperimentTrafficFloor {
    final week = latest;
    if (week == null) {
      return false;
    }
    return week.storeListingVisitors >= 100 || week.firstTimeInstallers >= 30;
  }
}

List<PlayAcquisitionWeek> parseAcquisitionLog(String source) {
  final rows = _parseCsv(source);
  if (rows.isEmpty) {
    throw const FormatException('Play acquisition log CSV is empty');
  }

  final header = rows.first.map((cell) => cell.trim()).toList(growable: false);
  final missing = requiredAcquisitionColumns.where(
    (column) => !header.contains(column),
  );
  if (missing.isNotEmpty) {
    throw FormatException(
      'Play acquisition log missing columns: ${missing.join(', ')}',
    );
  }

  final weeks = <PlayAcquisitionWeek>[];
  for (final row in rows.skip(1)) {
    if (row.every((cell) => cell.trim().isEmpty)) {
      continue;
    }

    String field(String column) {
      final index = header.indexOf(column);
      return index == -1 || index >= row.length ? '' : row[index].trim();
    }

    weeks.add(
      PlayAcquisitionWeek(
        weekStart: field('week_start'),
        weekEnd: field('week_end'),
        storeListingVisitors: _intField(field('store_listing_visitors')),
        firstTimeInstallers: _intField(field('first_time_installers')),
        trackerInstalls: _intField(field('tracker_installs')),
        activatedGroups: _intField(field('activated_groups')),
        variant: field('variant'),
        decision: field('decision'),
        notes: field('notes'),
        topCountry: field('top_country'),
        topLanguage: field('top_language'),
        searchTerms: field('search_terms'),
      ),
    );
  }

  return weeks;
}

PlayAcquisitionSummary summarizeAcquisitionLog(
  List<PlayAcquisitionWeek> weeks, {
  first100.TrackerSummary? trackerSummary,
}) {
  final draft = PlayAcquisitionSummary(
    weeks: weeks,
    trackerSummary: trackerSummary,
    recommendedNextAction: '',
  );

  return PlayAcquisitionSummary(
    weeks: weeks,
    trackerSummary: trackerSummary,
    recommendedNextAction: _recommendNextAction(draft),
  );
}

String renderMarkdown(PlayAcquisitionSummary summary) {
  final buffer = StringBuffer()
    ..writeln('# Rihla Play Acquisition Summary')
    ..writeln();

  final latest = summary.latest;
  if (latest == null) {
    buffer
      ..writeln('No Play acquisition weeks recorded yet.')
      ..writeln()
      ..writeln('## Recommended Next Action')
      ..writeln()
      ..writeln(summary.recommendedNextAction);
    return buffer.toString();
  }

  buffer
    ..writeln('Latest week: ${latest.weekStart} to ${latest.weekEnd}')
    ..writeln()
    ..writeln('## Latest Play Metrics')
    ..writeln()
    ..writeln('| Metric | Value |')
    ..writeln('|---|---:|')
    ..writeln('| Store listing visitors | ${latest.storeListingVisitors} |')
    ..writeln('| First-time installers | ${latest.firstTimeInstallers} |')
    ..writeln(
      '| Store listing conversion rate | ${_percent(latest.conversionRate)} |',
    )
    ..writeln('| Tracker installs | ${latest.trackerInstalls}/100 installs |')
    ..writeln('| Activated groups | ${latest.activatedGroups}/20 |')
    ..writeln()
    ..writeln('## Listing Experiment Gate')
    ..writeln()
    ..writeln(
      summary.hasExperimentTrafficFloor
          ? 'Traffic floor met: at least 100 Store listing visitors or 30 first-time installers recorded.'
          : 'Do not start a Play experiment: keep collecting traffic until there are at least 100 Store listing visitors or 30 first-time installers.',
    );

  final tracker = summary.trackerSummary;
  if (tracker != null) {
    buffer
      ..writeln()
      ..writeln('## First-100 Tracker Cross-Check')
      ..writeln()
      ..writeln('| Metric | Current | Target |')
      ..writeln('|---|---:|---:|')
      ..writeln('| Named champions | ${tracker.namedChampions} | 40 |')
      ..writeln(
        '| Total installs reported | ${tracker.installsReported} | 100 |',
      )
      ..writeln('| Activated groups | ${tracker.activatedGroups} | 20 |')
      ..writeln('| Real expenses/settlements | ${tracker.realActions} | 50 |');
  }

  buffer
    ..writeln()
    ..writeln('## Latest Context')
    ..writeln()
    ..writeln('- Variant: ${_valueOrDash(latest.variant)}')
    ..writeln('- Decision: ${_valueOrDash(latest.decision)}')
    ..writeln('- Top country: ${_valueOrDash(latest.topCountry)}')
    ..writeln('- Top language: ${_valueOrDash(latest.topLanguage)}')
    ..writeln('- Search terms: ${_valueOrDash(latest.searchTerms)}')
    ..writeln('- Notes: ${_valueOrDash(latest.notes)}')
    ..writeln()
    ..writeln('## Recommended Next Action')
    ..writeln()
    ..writeln(summary.recommendedNextAction);

  return buffer.toString();
}

String buildAcquisitionLogTemplate() {
  return [
    [...requiredAcquisitionColumns, ...optionalAcquisitionColumns].join(','),
    '2026-06-27,2026-07-03,0,0,0,0,Current listing,,'
        'baseline week,,,',
    '',
  ].join('\n');
}

Future<void> writeAcquisitionLogTemplate(String outputPath) async {
  await File(outputPath).writeAsString(buildAcquisitionLogTemplate());
}

Future<void> main(List<String> args) async {
  String? acquisitionPath;
  String trackerPath = first100.defaultTrackerPath;
  String? templateOutputPath;

  for (final arg in args) {
    if (arg.startsWith('--write-template=')) {
      templateOutputPath = arg.substring('--write-template='.length);
    } else if (!arg.startsWith('--') && acquisitionPath == null) {
      acquisitionPath = arg;
    } else if (!arg.startsWith('--')) {
      trackerPath = arg;
    }
  }

  if (templateOutputPath != null) {
    await writeAcquisitionLogTemplate(templateOutputPath);
    stderr.writeln(
      'Wrote Play acquisition log template to $templateOutputPath',
    );
    return;
  }

  if (acquisitionPath == null) {
    stderr.writeln(
      'Usage: dart tool/play_acquisition_summary.dart '
      '<private-play-acquisition-log.csv> [tracker.csv]\n'
      '   or: dart tool/play_acquisition_summary.dart '
      '--write-template=<private-play-acquisition-log.csv>',
    );
    exit(64);
  }

  final acquisitionSource = await File(acquisitionPath).readAsString();
  final trackerSource = await File(trackerPath).readAsString();
  final trackerRows = first100.parseTrackerCsv(trackerSource);
  final trackerSummary = first100.summarizeTracker(trackerRows);
  final weeks = parseAcquisitionLog(acquisitionSource);
  final summary = summarizeAcquisitionLog(
    weeks,
    trackerSummary: trackerSummary,
  );

  stdout.write(renderMarkdown(summary));
}

String _recommendNextAction(PlayAcquisitionSummary summary) {
  final latest = summary.latest;
  if (latest == null) {
    return 'Create the private Play acquisition log, add the latest Play Console week, and keep recruiting champions.';
  }

  final tracker = summary.trackerSummary;
  if (tracker != null && tracker.namedChampions < 10) {
    return 'Fill the first 10 champion names, confirm Play access, and send the Day-1 messages before any Play Store experiment.';
  }
  if (!summary.hasExperimentTrafficFloor) {
    return 'Do not start a Play experiment yet. Keep the current listing and collect more Store listing visitors or first-time installer data.';
  }
  if (latest.activatedGroups == 0) {
    return 'Do not call a store variant successful until Play installs produce activated groups in the first-100 tracker.';
  }
  return 'Run one Play Store experiment from the ASO backlog and compare installer conversion against tracker activation.';
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

int _intField(String value) {
  if (value.isEmpty) {
    return 0;
  }
  return int.tryParse(value) ?? 0;
}

String _percent(double value) {
  return '${(value * 100).round()}%';
}

String _valueOrDash(String value) => value.isEmpty ? '-' : value;
