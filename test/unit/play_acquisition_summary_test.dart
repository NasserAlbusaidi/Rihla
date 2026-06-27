import 'package:flutter_test/flutter_test.dart';

// Tool scripts in `tool/` are not packaged — import relatively.
import '../../tool/first_100_summary.dart' as first100;
import '../../tool/play_acquisition_summary.dart' as acquisition;

void main() {
  test('renders latest Play metrics and computes conversion rate', () {
    final weeks = acquisition.parseAcquisitionLog('''
week_start,week_end,store_listing_visitors,first_time_installers,tracker_installs,activated_groups,variant,decision,notes
2026-06-20,2026-06-26,80,8,8,1,Current listing,Collect baseline,alpha access friction
2026-06-27,2026-07-03,120,24,20,4,Current listing,,first warm batch sent
''');

    final summary = acquisition.summarizeAcquisitionLog(weeks);
    final rendered = acquisition.renderMarkdown(summary);

    expect(summary.latest!.storeListingVisitors, 120);
    expect(summary.latest!.firstTimeInstallers, 24);
    expect(summary.latest!.conversionRate, closeTo(0.20, 0.0001));
    expect(summary.hasExperimentTrafficFloor, isTrue);
    expect(rendered, contains('| Store listing visitors | 120 |'));
    expect(rendered, contains('| First-time installers | 24 |'));
    expect(rendered, contains('| Store listing conversion rate | 20% |'));
    expect(rendered, contains('Run one Play Store experiment'));
  });

  test('blocks listing experiments until champion outreach starts', () {
    final trackerRows = first100.parseTrackerCsv('''
slot,champion,segment,use_case,contact_channel,tester_added,first_contact_date,follow_up_date,group_created,invite_sent,installs_reported,joined_count,expenses_count,settlements_count,activated_group,top_blocker,feedback,next_action
1,,Travel crews,Trip expenses,WhatsApp,no,,,no,no,0,0,0,0,no,,,fill champion name and send first ask
''');
    final trackerSummary = first100.summarizeTracker(trackerRows);
    final weeks = acquisition.parseAcquisitionLog('''
week_start,week_end,store_listing_visitors,first_time_installers,tracker_installs,activated_groups,variant,decision,notes
2026-06-27,2026-07-03,40,5,0,0,Current listing,,no champion outreach yet
''');

    final summary = acquisition.summarizeAcquisitionLog(
      weeks,
      trackerSummary: trackerSummary,
    );
    final rendered = acquisition.renderMarkdown(summary);

    expect(summary.hasExperimentTrafficFloor, isFalse);
    expect(summary.recommendedNextAction, contains('Fill the first 10'));
    expect(rendered, contains('Do not start a Play experiment'));
    expect(rendered, contains('0/100 installs'));
  });

  test('builds a private acquisition log template without tester data', () {
    final template = acquisition.buildAcquisitionLogTemplate();

    expect(template, startsWith('week_start,week_end,store_listing_visitors'));
    expect(template, contains('first_time_installers'));
    expect(template, contains('search_terms'));
    expect(template, isNot(contains('champion')));
    expect(template, isNot(contains('google_play_email')));
  });

  test('throws when acquisition log columns are missing', () {
    expect(
      () =>
          acquisition.parseAcquisitionLog('week_start,visitors\n2026-06-27,1'),
      throwsFormatException,
    );
  });
}
