import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/home/widgets/balance_hero_card.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/star_grid.dart';

/// Night star-grid (#900 PR-3 comp 2, LOCKED hero-scoped decision): the
/// balance hero card paints [StarGridPainter] behind its content ONLY in
/// dark theme, clipped to the card's own radius.
void main() {
  CrossGroupBalance omr(String net) {
    final n = Decimal.parse(net);
    return (
      byCurrency: [
        (
          currency: 'OMR',
          net: n,
          owedToUser: n > Decimal.zero ? n : Decimal.zero,
          userOwes: n < Decimal.zero ? n.abs() : Decimal.zero,
        ),
      ],
      groupCount: 1,
      isLoading: false,
    );
  }

  Widget buildCard(ThemeData theme) {
    return ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('test-user-id'),
        userGroupsProvider.overrideWith((ref) => Stream.value(const [])),
        crossGroupHomeBalanceProvider.overrideWith(
          (ref) => AsyncValue.data((balance: omr('5.000'), partial: false)),
        ),
      ],
      child: MaterialApp(
        theme: theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: BalanceHeroCard()),
      ),
    );
  }

  testWidgets('dark theme paints the star-grid behind the hero content', (
    tester,
  ) async {
    await tester.pumpWidget(buildCard(AppTheme.darkTheme));
    await tester.pump();

    final customPaints = tester.widgetList<CustomPaint>(
      find.byType(CustomPaint),
    );
    expect(
      customPaints.any((cp) => cp.painter is StarGridPainter),
      isTrue,
      reason: 'dark hero should paint a StarGridPainter',
    );
  });

  testWidgets('light theme shows no star-grid', (tester) async {
    await tester.pumpWidget(buildCard(AppTheme.lightTheme));
    await tester.pump();

    final customPaints = tester.widgetList<CustomPaint>(
      find.byType(CustomPaint),
    );
    expect(
      customPaints.any((cp) => cp.painter is StarGridPainter),
      isFalse,
      reason: 'light hero must not paint the night star-grid',
    );
  });
}
