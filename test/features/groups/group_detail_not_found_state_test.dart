import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/widgets/group_detail/not_found_state.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/empty_state_view.dart';

void main() {
  testWidgets('NotFoundState renders the group-not-found empty state', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Deliberately NON-const construction (runtime .join() defeats const
    // folding): a const NotFoundState is canonicalized at kernel-compile
    // time, so the constructor line records no runtime hit in multi-file
    // coverage runs — the 90% diff floor then sees 0/1 on the very line
    // this test exists to cover.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NotFoundState(groupId: ['group-1'].join()),
      ),
    );
    // EmptyStateView schedules a flutter_animate entrance ticker — drain it
    // or teardown throws "A Timer is still pending".
    await tester.pumpAndSettle();

    expect(find.byType(EmptyStateView), findsOneWidget);
    expect(find.text(l10n.groupNotFoundTitle), findsOneWidget);
    expect(find.text(l10n.groupNotFoundMessage), findsOneWidget);
    expect(find.text(l10n.groupBackHome), findsOneWidget);
  });
}
