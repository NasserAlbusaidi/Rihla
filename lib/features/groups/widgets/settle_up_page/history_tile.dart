import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/utils/bidi.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/spacing_tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/share_helper.dart';
import '../../../../shared/widgets/directional_icon.dart';
import '../../../../shared/widgets/r_amount.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../ledger/models/settlement_model.dart';
import '../../../ledger/utils/correction_note.dart';
import '../../keys/group_keys.dart';

class HistoryTile extends StatelessWidget {
  const HistoryTile({
    super.key,
    required this.settlement,
    required this.displayNames,
    required this.subjectName,
    required this.index,
    this.onCorrect,
    this.overrideAmount,
    this.isCorrectedLogical = false,
    this.onCorrectLogical,
    this.soloCorrectionHidden = false,
  });

  final Settlement settlement;
  final Map<String, String> displayNames;
  final String subjectName;
  final int index;

  /// #283: when non-null AND both party ids are present, this tile shows a
  /// "correct this payment" affordance that records an offsetting reverse
  /// settlement after a confirmation dialog.
  final void Function(Settlement settlement)? onCorrect;

  /// #889: hides the SOLO Correct button (`onCorrect` branch only, never the
  /// logical branch) when [settlement] is already a marked correction or a
  /// bounded-legacy note-only correction target — computed by the caller from
  /// its OWN screen's settlement list (`isSoloCorrectionHidden`).
  final bool soloCorrectionHidden;

  /// #753 logical-row overrides (set only when this tile renders a
  /// [LogicalHistoryRow]). [overrideAmount] is the logical total A (shown +
  /// confirmed instead of the representative doc's slice); [isCorrectedLogical]
  /// forces the "Correction" treatment + hides the correct button (idempotency);
  /// [onCorrectLogical] is the atomic logical-correction driver (used instead of
  /// [onCorrect], which targets a single doc).
  final Decimal? overrideAmount;
  final bool isCorrectedLogical;
  final VoidCallback? onCorrectLogical;

  /// Confirms then hands the original [settlement] to [onCorrect]. The dialog
  /// describes the REVERSE flow (the recipient pays the payer back) and reuses
  /// the tile's already-resolved [payerName]/[recipientName] locals.
  Future<void> _confirmAndCorrect(
    BuildContext context,
    String payerName,
    String recipientName,
  ) async {
    final l10n = context.l10n;
    // #1201: amount embedded in a composed l10n sentence — stays formatCurrency;
    // RAmount governs standalone displayed amounts (DESIGN.md §8).
    final amountStr = AppFormatters.formatCurrency(
      overrideAmount ?? settlement.amount,
      settlement.currency,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.settleUpCorrectTitle),
        content: Text(
          // #1216b: isolate the names at the dialog arg — never the
          // payerName/recipientName locals (they also feed the shared receipt).
          l10n.settleUpCorrectBody(
            amountStr,
            bidiIsolate(recipientName),
            bidiIsolate(payerName),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.settleUpCorrectConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // #753: a logical row reverses the whole settle-up by id; a solo row hands
    // back the single doc (#283).
    if (onCorrectLogical != null) {
      onCorrectLogical!();
    } else {
      onCorrect!(settlement);
    }
  }

  /// Composes the plain-text receipt shared via [shareText] (#359). Built only
  /// from persisted fields — payer/recipient, amount, date, group/event name,
  /// and the note when present (payment method is never persisted, so it is
  /// not claimed here). The amount is formatted code-first (#144) and stays LTR.
  String _composeReceipt(
    BuildContext context,
    String payerName,
    String recipientName,
    String dateStr,
  ) {
    final l10n = context.l10n;
    final lines = <String>[
      l10n.settleUpReceiptLine(
        payerName,
        recipientName,
        AppFormatters.formatCurrency(
          overrideAmount ?? settlement.amount,
          settlement.currency,
        ),
      ),
      l10n.settleUpReceiptContext(dateStr, subjectName),
    ];
    final note = settlement.note?.trim();
    if (note != null && note.isNotEmpty) {
      lines.add(note);
    }
    lines.add(l10n.settleUpReceiptFooter);
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    const spacing = AppSpacingTokens.standard;
    final payerId = settlement.payerParticipantId;
    final recipientId = settlement.recipientParticipantId;
    final payerName =
        (payerId == null ? null : displayNames[payerId]) ??
        settlement.payerName ??
        context.l10n.settleUpUnknown;
    final recipientName =
        (recipientId == null ? null : displayNames[recipientId]) ??
        settlement.recipientName ??
        context.l10n.settleUpUnknown;
    // `useNativeDigits = false` enforces Western digits (DEC-5/#145): the
    // generated `ar` DateSymbols carry ZERODIGIT: '٠', which intl adopts by
    // default per-locale, so without this the digits render Arabic-Indic
    // (#1215).
    final dateStr = (DateFormat.MMMd(
      Localizations.localeOf(context).toLanguageTag(),
    )..useNativeDigits = false).format(settlement.settledAt);
    // #567: a reversing correction must read as a correction, not as another
    // payment. Mark it with a reversal icon + label instead of the green tick.
    // #753: a corrected LOGICAL row reads the same way (its representative is an
    // original, so the note-based check alone would miss it).
    final isCorrection =
        isCorrectedLogical || isCorrectionNote(settlement.note);
    final accent = isCorrection
        ? context.colors.textSecondary
        : context.colors.success;

    return Container(
      margin: EdgeInsets.only(bottom: spacing.space8),
      decoration: BoxDecoration(
        color: context.colors.cardSurface,
        borderRadius: BorderRadius.circular(spacing.radiusMedium),
        border: Border.all(color: context.colors.rule),
        boxShadow: context.shadows.raised,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: spacing.space16,
        vertical: spacing.space12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCorrection ? Iconsax.undo : Iconsax.tick_circle,
                  size: 16,
                  color: accent,
                ),
              ),
              SizedBox(width: spacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isCorrection) ...[
                      Text(
                        context.l10n.settleUpCorrectionTag,
                        style: AppTypography.sans(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: context.colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    RichText(
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 13,
                          color: context.colors.textPrimary,
                        ),
                        children: [
                          TextSpan(
                            // #1216b: isolate the span (not the local — it feeds
                            // the shared receipt too).
                            text: bidiIsolate(payerName),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(
                            text: ' ${context.l10n.settleUpPaidConnector} ',
                          ),
                          TextSpan(
                            text: bidiIsolate(recipientName),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateStr,
                      style: AppTypography.sans(
                        fontSize: 11,
                        color: context.colors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              RAmount(
                value: overrideAmount ?? settlement.amount,
                currency: settlement.currency,
                size: 14,
                weight: FontWeight.w700,
                tone: AmountTone.ink,
              ),
            ],
          ),
          SizedBox(height: spacing.space4),
          // Actions live on their own trailing line: visible labels replace
          // the old tooltip-only icons (invisible on touch — a high-stakes
          // money correction shouldn't rely on icon-shape recognition), and
          // the labelled buttons don't fight the fixed-width amount for row
          // space on narrow screens (the old single-row layout overflowed
          // at 320px with long names). Wrap, not Row: two labelled buttons
          // exceed 320px, so they flow to a second line instead of clipping.
          Wrap(
            alignment: WrapAlignment.end,
            spacing: spacing.space4,
            children: [
              // #283: correct a recorded payment by recording an offsetting
              // reverse settlement (append-only). Shown only when a correction
              // driver is wired AND both party ids are present (the offset needs
              // both to target). Keyed on the newest tile for a stable test hook.
              // #752/#753: a SOLO row keeps one-tap single-doc correction but
              // ONLY when untagged (groupSettleUpId == null) — a tagged doc must
              // not be piecemeal-corrected. A LOGICAL row (onCorrectLogical set)
              // reverses the whole settle-up atomically and hides once corrected
              // (isCorrectedLogical → onCorrectLogical passed null upstream).
              if (((onCorrect != null &&
                          settlement.groupSettleUpId == null &&
                          !soloCorrectionHidden) ||
                      onCorrectLogical != null) &&
                  payerId != null &&
                  payerId.isNotEmpty &&
                  recipientId != null &&
                  recipientId.isNotEmpty) ...[
                TextButton.icon(
                  key: index == 0 ? GroupKeys.settleUpCorrectButton : null,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.standard,
                    minimumSize: const Size(0, 40),
                    padding: EdgeInsets.symmetric(horizontal: spacing.space8),
                    foregroundColor: context.colors.textSecondary,
                  ),
                  icon: Icon(
                    Iconsax.undo,
                    size: 14,
                    color: context.colors.textSecondary,
                  ),
                  label: Text(
                    context.l10n.settleUpCorrect,
                    style: AppTypography.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.22,
                    ),
                  ),
                  onPressed: () =>
                      _confirmAndCorrect(context, payerName, recipientName),
                ),
              ],
              // #359: share a plain-text receipt of this recorded payment. The
              // Builder gives shareText() the button's own render box as the
              // popover origin (non-zero on iPad); never call Share.share raw.
              Builder(
                builder: (buttonContext) => TextButton.icon(
                  // Key only the newest tile so a single, predictable target
                  // anchors widget tests; every tile is still shareable.
                  key: index == 0 ? GroupKeys.settleUpShareReceiptButton : null,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.standard,
                    minimumSize: const Size(0, 40),
                    padding: EdgeInsets.symmetric(horizontal: spacing.space8),
                    foregroundColor: context.colors.primary,
                  ),
                  icon: DirectionalIcon(
                    Iconsax.send_2,
                    size: 14,
                    color: context.colors.primary,
                  ),
                  label: Text(
                    context.l10n.settleUpShareReceipt,
                    style: AppTypography.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.22,
                    ),
                  ),
                  onPressed: () => shareText(
                    buttonContext,
                    _composeReceipt(
                      buttonContext,
                      payerName,
                      recipientName,
                      dateStr,
                    ),
                    subject: context.l10n.settleUpReceiptShareSubject,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: index * 40)).slideY(begin: 0.08, curve: Curves.easeOutCubic);
  }
}
