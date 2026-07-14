import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/models/split_mode.dart';
import 'mode_chip.dart';
import 'mode_help.dart';

/// split-clarity — the "How" control. All five split options (the four
/// arithmetic modes + Itemized) are peers, each an icon + label chip, wrapping
/// so nothing truncates (fixes the old sheet-only 5-chip ellipsis/RTL trap). A
/// one-line helper under the chips explains the selected option. Itemized is a
/// first-class chip here, not a hidden 5th tab inside the custom-split sheet.
class ModeSegment extends StatelessWidget {
  const ModeSegment({
    super.key,
    required this.mode,
    required this.isItemized,
    required this.enabled,
    required this.onPick,
    required this.onPickItemized,
  });

  final SplitMode mode;

  /// True when the expense carries a `splitExplanation` (#203). Itemized
  /// persists as `SplitMode.exact`, so selection keys off this flag FIRST —
  /// otherwise a reopened itemized expense would highlight "Exact".
  final bool isItemized;
  final bool enabled;
  final ValueChanged<SplitMode> onPick;
  final VoidCallback onPickItemized;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final modes = <(SplitMode, IconData, String)>[
      (SplitMode.equally, Iconsax.element_equal, l10n.splitModeEqually),
      (SplitMode.shares, Iconsax.chart_2, l10n.splitModeShares),
      (SplitMode.exact, Iconsax.hashtag, l10n.editorSplitModeExactShort),
      (SplitMode.percent, Iconsax.percentage_square, l10n.splitModePercent),
    ];
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (m, icon, label) in modes)
                ModeChip(
                  icon: icon,
                  label: label,
                  selected: !isItemized && m == mode,
                  onTap: enabled ? () => onPick(m) : null,
                ),
              // Itemized produces an exact split under the hood; the parent
              // opens the itemized editor directly (no "pick Exact first").
              ModeChip(
                icon: Iconsax.receipt_item,
                label: l10n.editorSplitItemized,
                selected: isItemized,
                onTap: enabled ? onPickItemized : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ModeHelp(mode: mode, isItemized: isItemized),
        ],
      ),
    );
  }
}
