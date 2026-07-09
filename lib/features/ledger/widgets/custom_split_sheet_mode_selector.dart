part of 'custom_split_sheet.dart';

// ───────────────────────── mode selector + participant rows
//
// The segmented mode tab-bar (_ModeSegmented + _SegChip) and the body that
// fans one _ParticipantRow per participant. Prop-driven by _CustomSplitSheetState
// (mode/itemized flags + the shares/exact/percent controller maps + callbacks);
// owns no controller. A part-of the custom_split_sheet library (shared scope).

// ───────────────────────────────────────────────────────────── segmented

class _ModeSegmented extends StatelessWidget {
  const _ModeSegmented({
    required this.itemized,
    required this.mode,
    required this.onMode,
    required this.onItemized,
  });

  /// Whether the Itemized pseudo-tab is the active selection (#203 S2).
  final bool itemized;
  final SplitMode mode;
  final ValueChanged<SplitMode> onMode;
  final VoidCallback onItemized;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final inset = context.spacing.space4;
    // #1067 §4: keep the painted segmented track compact and center it
    // behind a separate 44dp hit layer; the original 4dp horizontal inset
    // remains visual spacing between the track edge and the five tabs.
    return SizedBox(
      key: const Key('split_mode_segment'),
      height: 44,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            top: inset / 2,
            bottom: inset / 2,
            child: DecoratedBox(
              key: const Key('split_mode_segment_track'),
              decoration: BoxDecoration(
                color: colors.inputFill,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: Row(
              children: [
                // The four real modes — selected only when not in itemized
                // mode.
                for (final m in SplitMode.values)
                  Expanded(
                    child: _SegChip(
                      label: splitModeDisplayName(m, context.l10n),
                      selected: !itemized && m == mode,
                      onTap: () => onMode(m),
                    ),
                  ),
                // Itemized is a 5th option that PRODUCES an exact split
                // (#203 S2).
                Expanded(
                  child: _SegChip(
                    label: context.l10n.editorSplitItemized,
                    selected: itemized,
                    onTap: onItemized,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SegChip extends StatelessWidget {
  const _SegChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // #1067 §4: keep the full-width segmented pill compact while its
        // transparent, opaque-to-hit-testing wrapper reaches the 44dp floor.
        child: SizedBox(
          height: 44,
          child: Center(
            child: SizedBox(
              width: double.infinity,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: EdgeInsets.symmetric(
                  vertical: context.spacing.space8,
                ),
                decoration: BoxDecoration(
                  color: selected ? colors.cardSurface : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: selected ? context.shadows.raised : null,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTypography.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? colors.textPrimary
                        : colors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────── mode body

class _ModeBody extends StatelessWidget {
  const _ModeBody({
    super.key,
    required this.mode,
    required this.participants,
    required this.total,
    required this.currency,
    required this.shares,
    required this.exactCtrls,
    required this.percentCtrls,
    required this.totalShares,
    required this.onSharesChanged,
    required this.onAmountChanged,
  });

  final SplitMode mode;
  final List<SplitParticipant> participants;
  final Decimal total;
  final String currency;
  final Map<String, int> shares;
  final Map<String, TextEditingController> exactCtrls;
  final Map<String, TextEditingController> percentCtrls;
  final int totalShares;
  final VoidCallback onSharesChanged;
  final VoidCallback onAmountChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return Container(
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(spacing.radiusLarge),
        boxShadow: context.shadows.raised,
      ),
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space16),
      child: Column(
        children: [
          for (var i = 0; i < participants.length; i++)
            _ParticipantRow(
              participant: participants[i],
              mode: mode,
              total: total,
              currency: currency,
              shares: shares,
              totalShares: totalShares,
              exactCtrl: exactCtrls[participants[i].id],
              percentCtrl: percentCtrls[participants[i].id],
              showDivider: i < participants.length - 1,
              onSharesChanged: onSharesChanged,
              onAmountChanged: onAmountChanged,
              equalCount: participants.length,
            ),
        ],
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.participant,
    required this.mode,
    required this.total,
    required this.currency,
    required this.shares,
    required this.totalShares,
    required this.exactCtrl,
    required this.percentCtrl,
    required this.showDivider,
    required this.onSharesChanged,
    required this.onAmountChanged,
    required this.equalCount,
  });

  final SplitParticipant participant;
  final SplitMode mode;
  final Decimal total;
  final String currency;
  final Map<String, int> shares;
  final int totalShares;
  final TextEditingController? exactCtrl;
  final TextEditingController? percentCtrl;
  final bool showDivider;
  final VoidCallback onSharesChanged;
  final VoidCallback onAmountChanged;
  final int equalCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(vertical: context.spacing.space12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: showDivider ? colors.rule : Colors.transparent,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          RAvatar(name: participant.name, size: 32),
          SizedBox(width: context.spacing.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        participant.name,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    if (participant.role != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        participant.role!,
                        style: AppTypography.sans(
                          fontSize: 11,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
                // #278: flag a placeholder member who hasn't joined yet.
                if (participant.isShadow)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      context.l10n.editorShadowProfile,
                      style: AppTypography.sans(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                if (mode == SplitMode.equally || mode == SplitMode.shares)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progressValue,
                        minHeight: 4,
                        backgroundColor: colors.rule,
                        valueColor: AlwaysStoppedAnimation(colors.primary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(width: context.spacing.space12),
          SizedBox(
            width: 124,
            child: _Editor(
              mode: mode,
              total: total,
              currency: currency,
              shares: shares,
              participantId: participant.id,
              totalShares: totalShares,
              exactCtrl: exactCtrl,
              percentCtrl: percentCtrl,
              onSharesChanged: onSharesChanged,
              onAmountChanged: onAmountChanged,
              equalCount: equalCount,
            ),
          ),
        ],
      ),
    );
  }

  double get _progressValue {
    switch (mode) {
      case SplitMode.equally:
        if (equalCount == 0) return 0;
        return 1 / equalCount;
      case SplitMode.shares:
        if (totalShares == 0) return 0;
        return (shares[participant.id] ?? 0) / totalShares;
      case SplitMode.exact:
      case SplitMode.percent:
        return 0;
    }
  }
}
