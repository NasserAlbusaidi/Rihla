import 'package:flutter/material.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/models/split_mode.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';

/// The one-line explainer under the chips for the currently selected mode —
/// the "clear" half of "every option clear and visible".
class ModeHelp extends StatelessWidget {
  const ModeHelp({super.key, required this.mode, required this.isItemized});

  final SplitMode mode;
  final bool isItemized;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final String text;
    if (isItemized) {
      text = l10n.splitModeHelpItemized;
    } else {
      switch (mode) {
        case SplitMode.equally:
          text = l10n.splitModeHelpEqually;
        case SplitMode.shares:
          text = l10n.splitModeHelpShares;
        case SplitMode.exact:
          text = l10n.splitModeHelpExact;
        case SplitMode.percent:
          text = l10n.splitModeHelpPercent;
      }
    }
    return Text(
      text,
      style: AppTypography.sans(
        fontSize: 12,
        color: context.colors.textSecondary,
      ),
    );
  }
}
