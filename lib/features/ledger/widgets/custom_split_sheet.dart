import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/r_amount.dart';

/// Split modes shown on the custom-split sheet. Only [equally] is wired to
/// the underlying expense model today; the others are surfaced as "Soon"
/// placeholders to preserve the wireframe's segmented control layout.
enum SplitMode { equally, shares, exact, percent }

/// Bottom-sheet split editor matching Hi_Sheet_Split (tier 6).
///
/// Renders the segmented mode picker, per-person rows with progress bars and
/// share amounts, and a total footer. Read-only: the user cannot yet adjust
/// weights — tapping the non-equal modes shows a "Soon" snackbar.
///
/// Returns `true` if the user tapped Apply (Equally remains the active mode),
/// `false`/`null` on Cancel or dismissal.
Future<bool?> showCustomSplitSheet(
  BuildContext context, {
  required String title,
  required Decimal total,
  required String currency,
  required List<SplitParticipant> participants,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: context.colors.scaffoldBackground,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => CustomSplitSheet(
      title: title,
      total: total,
      currency: currency,
      participants: participants,
    ),
  );
}

class SplitParticipant {
  const SplitParticipant({required this.id, required this.name, this.role});

  final String id;
  final String name;

  /// Optional small caption shown next to the name (e.g. "You", "Paid").
  final String? role;
}

class CustomSplitSheet extends StatefulWidget {
  const CustomSplitSheet({
    super.key,
    required this.title,
    required this.total,
    required this.currency,
    required this.participants,
  });

  final String title;
  final Decimal total;
  final String currency;
  final List<SplitParticipant> participants;

  @override
  State<CustomSplitSheet> createState() => _CustomSplitSheetState();
}

class _CustomSplitSheetState extends State<CustomSplitSheet> {
  SplitMode _mode = SplitMode.equally;

  Decimal _equalShare() {
    final n = widget.participants.isEmpty ? 1 : widget.participants.length;
    return (widget.total / Decimal.fromInt(n)).toDecimal(
      scaleOnInfinitePrecision: 3,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final share = _equalShare();
    final equalPct = widget.participants.isEmpty
        ? 0
        : (100 / widget.participants.length);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: spacing.space12),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.rule2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(height: spacing.space12),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.space24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Split how?',
                        style: AppTypography.display(
                          fontSize: 26,
                          color: colors.textPrimary,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${widget.title} · ',
                            style: AppTypography.sans(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                          ),
                          RAmount(
                            value: widget.total,
                            currency: widget.currency,
                            size: 12,
                            weight: FontWeight.w600,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: spacing.space16),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.space24),
            child: _ModeSegmented(
              mode: _mode,
              onChanged: (next) {
                if (next == SplitMode.equally) {
                  HapticService.selection();
                  setState(() => _mode = next);
                } else {
                  HapticService.lightClick();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${_modeLabel(next)} splits are coming soon.',
                        style: AppTypography.sans(fontSize: 13),
                      ),
                      duration: const Duration(milliseconds: 1800),
                    ),
                  );
                }
              },
            ),
          ),
          SizedBox(height: spacing.space16),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: spacing.space24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: colors.cardSurface,
                      borderRadius: BorderRadius.circular(spacing.radiusLarge),
                      boxShadow: context.shadows.raised,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        for (var i = 0; i < widget.participants.length; i++)
                          _ParticipantRow(
                            participant: widget.participants[i],
                            percent: equalPct.toDouble(),
                            share: share,
                            currency: widget.currency,
                            showDivider: i < widget.participants.length - 1,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'TOTAL',
                        style: AppTypography.mono(
                          fontSize: 10,
                          letterSpacing: 1.5,
                          color: colors.textSecondary,
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '100 %',
                            style: AppTypography.mono(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.success,
                            ),
                          ),
                          const SizedBox(width: 8),
                          RAmount(
                            value: widget.total,
                            currency: widget.currency,
                            size: 16,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.space24,
              spacing.space20,
              spacing.space24,
              spacing.space20,
            ),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: colors.rule2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: AppTypography.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        HapticService.medium();
                        Navigator.of(context).pop(true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.textOnPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Apply',
                        style: AppTypography.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.textOnPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _modeLabel(SplitMode mode) {
    switch (mode) {
      case SplitMode.equally:
        return 'Equally';
      case SplitMode.shares:
        return 'Shares';
      case SplitMode.exact:
        return 'Exact';
      case SplitMode.percent:
        return 'Percent';
    }
  }
}

class _ModeSegmented extends StatelessWidget {
  const _ModeSegmented({required this.mode, required this.onChanged});

  final SplitMode mode;
  final ValueChanged<SplitMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (final m in SplitMode.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(m),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: m == mode ? colors.cardSurface : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: m == mode ? context.shadows.raised : null,
                  ),
                  child: Text(
                    _label(m),
                    style: AppTypography.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: m == mode
                          ? colors.textPrimary
                          : colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _label(SplitMode m) {
    switch (m) {
      case SplitMode.equally:
        return 'Equally';
      case SplitMode.shares:
        return 'Shares';
      case SplitMode.exact:
        return 'Exact';
      case SplitMode.percent:
        return 'Percent';
    }
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.participant,
    required this.percent,
    required this.share,
    required this.currency,
    required this.showDivider,
  });

  final SplitParticipant participant;
  final double percent;
  final Decimal share;
  final String currency;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
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
          _Avatar(name: participant.name),
          const SizedBox(width: 12),
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
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (percent / 100).clamp(0, 1).toDouble(),
                    minHeight: 4,
                    backgroundColor: colors.rule,
                    valueColor: AlwaysStoppedAnimation(colors.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.rule2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${percent.round()} %',
                  style: AppTypography.mono(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              RAmount(
                value: share,
                currency: currency,
                size: 11,
                weight: FontWeight.w500,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: colors.selectionFill,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '·',
        style: AppTypography.sans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: colors.primary,
        ),
      ),
    );
  }
}
