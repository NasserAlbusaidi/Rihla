// #1193: Add/Edit Expense → "Where" card rows (Event, Date) that carry a
// `trailingText:` render their value in the horizontal MIDDLE of the row
// instead of pinned to the trailing edge, because the value Text is wrapped
// in a bare `Flexible` (flex:1, loose) competing 50/50 with the
// `Expanded(title/subtitle Column)` (flex:1). The loose Flexible sizes to the
// short value and is positioned right after the label's half — i.e. the
// row's centre. The sibling Currency row escapes this because it passes a
// non-flex `trailing:` widget, letting the Expanded label push it to the true
// trailing edge (mirrors the merged #1184 fix, commit 8330eefd).
//
// These tests measure geometry (position, not existence): the trailing
// value's trailing edge must sit within ~1.5px of the row's trailing edge, in
// both LTR (right edge) and RTL (left edge, proving the AlignmentDirectional
// mirror). Widget-existence assertions alone stayed green through #1182/#1184.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/ledger/widgets/expense_editor/info_row.dart';

Widget _wrap({required TextDirection direction}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Directionality(
      textDirection: direction,
      child: const Scaffold(
        body: InfoRow(title: 'Event', trailingText: 'Bali Getaway'),
      ),
    ),
  );
}

void main() {
  testWidgets('LTR: trailingText value is pinned to the row trailing '
      '(right) edge', (tester) async {
    await tester.pumpWidget(_wrap(direction: TextDirection.ltr));
    await tester.pumpAndSettle();

    final valueFinder = find.text('Bali Getaway');
    final rowFinder = find
        .ancestor(of: valueFinder, matching: find.byType(Row))
        .first;

    final valueRect = tester.getRect(valueFinder);
    final rowRect = tester.getRect(rowFinder);

    // Trailing edge in LTR is the right edge: the value's right edge must sit
    // essentially at the row's right edge (was ~centre before the fix).
    expect(
      valueRect.right,
      closeTo(rowRect.right, 1.5),
      reason:
          'value right=${valueRect.right} vs row right=${rowRect.right} — '
          'the trailing value is not pinned to the row trailing edge',
    );
  });

  testWidgets('RTL: trailingText value is pinned to the row trailing '
      '(left) edge', (tester) async {
    await tester.pumpWidget(_wrap(direction: TextDirection.rtl));
    await tester.pumpAndSettle();

    final valueFinder = find.text('Bali Getaway');
    final rowFinder = find
        .ancestor(of: valueFinder, matching: find.byType(Row))
        .first;

    final valueRect = tester.getRect(valueFinder);
    final rowRect = tester.getRect(rowFinder);

    // Trailing edge in RTL is the left edge (AlignmentDirectional mirror).
    expect(
      valueRect.left,
      closeTo(rowRect.left, 1.5),
      reason:
          'value left=${valueRect.left} vs row left=${rowRect.left} — '
          'the trailing value did not mirror to the RTL trailing edge',
    );
  });
}
