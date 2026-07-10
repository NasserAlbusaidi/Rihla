import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/models/split_mode.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../../events/models/event_model.dart';
import '../../groups/services/member_name_resolver.dart';
import '../models/expense_model.dart';
import '../models/split_explanation.dart';
import '../providers/expense_provider.dart';
import 'split_scope_selector.dart';

/// #485 / #627 perf seam — counts how often the card re-runs the
/// `allocateExpenseOwed` allocation. The parent `setState`s `_amount` on every
/// keystroke, so the card rebuilds per digit; the memo below recomputes `owed`
/// only when an actual money input changes. Reset in test `setUp`; production
/// never reads it. (Moved verbatim from the old `_SplitPreviewCard`.)
@visibleForTesting
int debugSplitPreviewOwedComputes = 0;

/// #485: the single "Split" card. Collapses the former three sections — Paid by
/// / Split between / How — into one coherent surface: a single payer control,
/// a plain-language scope segment, a split-mode segment, and the real per-person
/// figures (#242) with an "adds up to total" footer.
///
/// Pure layout/IA: it reuses [BalanceCalculator.allocateExpenseOwed] (#242) and
/// the existing weights sheet untouched, so there is no money/rules/schema
/// surface here. Money truth stays in `splitDistribution`.
class SplitCard extends StatefulWidget {
  const SplitCard({
    super.key,
    required this.event,
    required this.displayNames,
    required this.amount,
    required this.currency,
    required this.scope,
    required this.payerId,
    required this.selfId,
    required this.customSplitParticipants,
    required this.splitMode,
    required this.splitDistribution,
    required this.splitExplanation,
    required this.onChangePayer,
    required this.onScopeChanged,
    required this.onCustomSplitChanged,
    required this.onPickMode,
    required this.onPickItemized,
  });

  final Event event;

  /// #289 disambiguation map, owned and memoized by the parent (#627) and shared
  /// with every consumer. Render-only; write paths key by id.
  final Map<String, String> displayNames;
  final Decimal amount;
  final String currency;
  final ExpenseScope scope;
  final String? payerId;

  /// The current user's event-participant id, used only to highlight their own
  /// row. Null in tests without an auth override → no highlight (purely additive).
  final String? selfId;
  final Set<String> customSplitParticipants;
  final SplitMode splitMode;
  final Map<String, Decimal>? splitDistribution;
  final SplitExplanation? splitExplanation;

  /// Opens the single payer picker (`_PayerPickerSheet`, #280).
  final VoidCallback onChangePayer;
  final ValueChanged<ExpenseScope> onScopeChanged;
  final ValueChanged<Set<String>> onCustomSplitChanged;

  /// Equal → set inline (parent clears the distribution); shares/exact/percent →
  /// parent opens the existing weights sheet seeded with the requested mode.
  final ValueChanged<SplitMode> onPickMode;

  /// split-clarity: the user tapped the Itemized chip. Itemized is NOT a
  /// [SplitMode] (it persists as `exact` + a `splitExplanation`, #203), so it
  /// gets its own signal; the parent opens the itemized editor directly instead
  /// of routing through a mode the user didn't ask for.
  final VoidCallback onPickItemized;

  @override
  State<SplitCard> createState() => _SplitCardState();
}

class _SplitCardState extends State<SplitCard> {
  Map<String, Decimal>? _owed;

  bool get _isNonEqual =>
      widget.splitMode != SplitMode.equally &&
      widget.splitDistribution != null &&
      widget.splitDistribution!.isNotEmpty;

  bool get _isItemized => widget.splitExplanation != null;

  /// The participant ids the expense divides across, per scope — mirrors
  /// [BalanceCalculator] (and the parent's `_splitParticipantIds`), including
  /// the #247 empty-custom→global fallback.
  List<String> get _splitParticipantIds {
    switch (widget.scope) {
      case ExpenseScope.global:
      case ExpenseScope.subGroup:
        return widget.event.participantIds;
      case ExpenseScope.custom:
        return widget.customSplitParticipants.isEmpty
            ? widget.event.participantIds
            : widget.customSplitParticipants.toList();
      case ExpenseScope.personal:
        return widget.payerId != null ? [widget.payerId!] : const [];
    }
  }

  @override
  void initState() {
    super.initState();
    _recomputeOwed();
  }

  @override
  void didUpdateWidget(SplitCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_owedInputsChanged(oldWidget)) {
      _recomputeOwed();
    }
  }

  /// True when ANY input to `allocateExpenseOwed` changed (value-compared, safe
  /// against value-equal instances). Missing one would show a stale figure.
  bool _owedInputsChanged(SplitCard oldWidget) {
    return !identical(widget.event, oldWidget.event) ||
        widget.amount != oldWidget.amount ||
        widget.splitMode != oldWidget.splitMode ||
        widget.scope != oldWidget.scope ||
        widget.currency != oldWidget.currency ||
        widget.payerId != oldWidget.payerId ||
        !mapEquals(widget.splitDistribution, oldWidget.splitDistribution) ||
        !setEquals(
          widget.customSplitParticipants,
          oldWidget.customSplitParticipants,
        );
  }

  void _recomputeOwed() {
    debugSplitPreviewOwedComputes++;
    // #242/#853 WYSIWYG: every mode, including Equal, shows each person's REAL
    // owed amount via the same pure helper calculateBalances uses, so the
    // preview equals what gets persisted. Equal mode therefore gets the
    // allocator's currency quantization + last-recipient remainder. `onFallback:
    // null` keeps a transient/forged split silent.
    _owed = BalanceCalculator.allocateExpenseOwed(
      amount: widget.amount,
      splitMode: widget.splitMode,
      splitDistribution: widget.splitDistribution,
      scope: widget.scope,
      customSplitParticipants: widget.customSplitParticipants.toList(),
      payerId: widget.payerId ?? '',
      participantIds: widget.event.participantIds,
      currency: widget.currency,
      onFallback: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final ids = _splitParticipantIds;
    final count = ids.length;
    final canSplit = count >= 2;

    final payerId = widget.payerId ?? widget.event.participantIds.firstOrNull;
    final payerName = payerId == null
        ? l10n.editorSelectedPayer
        : widget.displayNames[payerId] ??
              widget.event.participantNames[payerId] ??
              l10n.editorMemberFallback;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space24),
      child: Container(
        decoration: BoxDecoration(
          color: colors.cardSurface,
          borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
          boxShadow: context.shadows.raised,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Paid by — the single payer control ───────────────────────
            _FieldLabel(l10n.editorPaidBy),
            const SizedBox(height: 8),
            _PayerInlineRow(
              name: payerName,
              onChange: widget.onChangePayer,
            ),

            const SizedBox(height: 18),

            // ── Who splits — plain-language scope ────────────────────────
            Row(
              children: [
                Expanded(child: _FieldLabel(l10n.editorWhoSplits)),
                if (widget.scope == ExpenseScope.global)
                  Text(
                    l10n.editorEventDefault,
                    style: AppTypography.caption(
                      context,
                      fontSize: 9,
                      letterSpacing: 1.6,
                      color: colors.textPrimary.withValues(alpha: 0.45),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _ScopeSegment(scope: widget.scope, onChanged: widget.onScopeChanged),
            if (widget.scope == ExpenseScope.custom) ...[
              const SizedBox(height: 14),
              CustomParticipantSelector(
                event: widget.event,
                customSplitParticipants: widget.customSplitParticipants,
                onCustomSplitChanged: widget.onCustomSplitChanged,
              ),
            ],

            const SizedBox(height: 18),

            // ── How — split mode ─────────────────────────────────────────
            _FieldLabel(l10n.editorHow),
            const SizedBox(height: 8),
            _ModeSegment(
              mode: widget.splitMode,
              isItemized: _isItemized,
              enabled: canSplit,
              onPick: widget.onPickMode,
              onPickItemized: widget.onPickItemized,
            ),

            if (canSplit) ...[
              const SizedBox(height: 14),
              Divider(height: 1, color: colors.rule),
              const SizedBox(height: 6),
              for (final id in ids) _personRow(context, id),
              const SizedBox(height: 12),
              _ReconcileFooter(
                descriptor: _descriptor(context),
                addsUpTo: l10n.editorSplitAddsUpTo(
                  AppFormatters.formatCurrency(widget.amount, widget.currency),
                ),
              ),
            ] else ...[
              const SizedBox(height: 10),
              // #152: with fewer than two eligible people there is no split, so
              // show the single coherent gate — never a finished "1 way · each".
              Text(
                l10n.editorPickAtLeastTwoToSplit,
                style: AppTypography.sans(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
              // #247: still show the single persisted participant's row (no
              // "each" descriptor / footer) so the preview reflects exactly the
              // chosen set — a custom split of one renders that one person.
              if (count == 1) ...[
                const SizedBox(height: 8),
                _personRow(context, ids.first),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _personRow(BuildContext context, String id) {
    final l10n = context.l10n;
    final name =
        widget.displayNames[id] ??
        widget.event.participantNames[id] ??
        l10n.editorMemberFallback;
    // #242/#853: every mode reads the REAL per-person owed from the allocator
    // (equal included), so the row figures reconcile to the total.
    final share = _owed![id] ?? Decimal.zero;
    return _SplitPersonRow(
      name: name,
      // #289: compact disambiguated label — first name, keeping the `(#…)`
      // discriminator only when two members collide (matches the old tile).
      label: MemberNameResolver.compactDisambiguated(name),
      share: share,
      currency: widget.currency,
      isPayer: id == widget.payerId,
      isSelf: widget.selfId != null && id == widget.selfId,
    );
  }

  /// The per-mode descriptor line: itemized item-count, "amounts vary", or the
  /// uniform "{amount} each". Keyed so the #203 itemized tests can scope to it
  /// (the mode segment carries its own "Exact" label that must not be confused
  /// with this descriptor).
  Widget _descriptor(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final style = AppTypography.sans(
      fontSize: 12,
      color: colors.textSecondary,
      fontWeight: FontWeight.w600,
    );
    final Widget inner;
    if (_isItemized) {
      inner = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.editorSplitItemized, style: style),
          Text('  ·  ', style: style),
          Text(
            l10n.itemizedNItems(widget.splitExplanation!.items.length),
            style: style,
          ),
        ],
      );
    } else if (_isNonEqual) {
      inner = Text(l10n.editorAmountsVary, style: style);
    } else {
      final count = _splitParticipantIds.length;
      final each = count == 0
          ? Decimal.zero
          : (widget.amount / Decimal.fromInt(count)).toDecimal(
              scaleOnInfinitePrecision: 3,
            );
      inner = Text(
        l10n.editorEachAmount(
          AppFormatters.formatCurrency(each, widget.currency),
        ),
        style: style,
      );
    }
    return KeyedSubtree(
      key: const Key('split_card_summary'),
      child: inner,
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.caption(
        context,
        fontSize: 10.5,
        letterSpacing: 1.0,
        fontWeight: FontWeight.w700,
        color: context.colors.textSecondary,
      ),
    );
  }
}

class _PayerInlineRow extends StatelessWidget {
  const _PayerInlineRow({required this.name, required this.onChange});

  final String name;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChange,
      child: Row(
        children: [
          RAvatar(name: name, size: 30),
          SizedBox(width: context.spacing.space12),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.sans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colors.inputFill,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: colors.rule2),
            ),
            child: Text(
              context.l10n.editorChange,
              style: AppTypography.sans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.primaryDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScopeSegment extends StatelessWidget {
  const _ScopeSegment({required this.scope, required this.onChanged});

  final ExpenseScope scope;
  final ValueChanged<ExpenseScope> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // subGroup is legacy/dead — collapse it onto "Everyone".
    final selected = scope == ExpenseScope.subGroup ? ExpenseScope.global : scope;
    return _Segmented<ExpenseScope>(
      value: selected,
      onChanged: onChanged,
      options: [
        (ExpenseScope.global, l10n.editorScopeGlobal),
        (ExpenseScope.custom, l10n.editorScopeCustom),
        (ExpenseScope.personal, l10n.editorScopePersonal),
      ],
    );
  }
}

/// split-clarity — the "How" control. All five split options (the four
/// arithmetic modes + Itemized) are peers, each an icon + label chip, wrapping
/// so nothing truncates (fixes the old sheet-only 5-chip ellipsis/RTL trap). A
/// one-line helper under the chips explains the selected option. Itemized is a
/// first-class chip here, not a hidden 5th tab inside the custom-split sheet.
class _ModeSegment extends StatelessWidget {
  const _ModeSegment({
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
                _ModeChip(
                  icon: icon,
                  label: label,
                  selected: !isItemized && m == mode,
                  onTap: enabled ? () => onPick(m) : null,
                ),
              // Itemized produces an exact split under the hood; the parent
              // opens the itemized editor directly (no "pick Exact first").
              _ModeChip(
                icon: Iconsax.receipt_item,
                label: l10n.editorSplitItemized,
                selected: isItemized,
                onTap: enabled ? onPickItemized : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ModeHelp(mode: mode, isItemized: isItemized),
        ],
      ),
    );
  }
}

/// One icon+label chip in the "How" control. Selected → saffron selection fill
/// + primary border/icon; otherwise the neutral input surface.
class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

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
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // #1067 §4: the opaque wrapper supplies the 44dp hit floor; the
        // widthFactor keeps this Wrap child intrinsic-width and its painted
        // pill vertically compact.
        child: SizedBox(
          height: 44,
          child: Center(
            widthFactor: 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 14, 8),
              decoration: BoxDecoration(
                color: selected ? colors.selectionFill : colors.inputFill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? colors.primary : colors.rule,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: selected
                        ? colors.primaryDark
                        : colors.textSecondary,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: AppTypography.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? colors.textPrimary
                          : colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The one-line explainer under the chips for the currently selected mode —
/// the "clear" half of "every option clear and visible".
class _ModeHelp extends StatelessWidget {
  const _ModeHelp({required this.mode, required this.isItemized});

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

/// Generic inline segmented control matching the signed-off #485 mockup. Equal
/// weight per segment; the active one lifts onto the card surface.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: colors.inputFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.rule),
        ),
        child: Row(
          children: [
            for (final (optValue, label) in options)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: optValue == value,
                  label: label,
                  onTap: enabled ? () => onChanged(optValue) : null,
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: enabled ? () => onChanged(optValue) : null,
                    // #1077 §4: the opaque wrapper supplies the 44dp hit
                    // floor (mirrors _ModeChip); Center keeps the painted
                    // pill at its compact vertical-8 padding while the
                    // infinite width still fills the equal-weight segment.
                    child: SizedBox(
                      height: 44,
                      child: Center(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: optValue == value
                                ? colors.cardSurface
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: optValue == value
                                ? context.shadows.raised
                                : null,
                          ),
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.sans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: optValue == value
                                  ? colors.textPrimary
                                  : colors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SplitPersonRow extends StatelessWidget {
  const _SplitPersonRow({
    required this.name,
    required this.label,
    required this.share,
    required this.currency,
    required this.isPayer,
    required this.isSelf,
  });

  /// Full disambiguated name — drives the stable avatar hue.
  final String name;

  /// Compact display label (first name + `(#…)` only on collision).
  final String label;
  final Decimal share;
  final String currency;
  final bool isPayer;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: EdgeInsets.symmetric(vertical: isSelf ? 2 : 0),
      padding: EdgeInsetsDirectional.fromSTEB(isSelf ? 8 : 0, 9, isSelf ? 8 : 0, 9),
      decoration: isSelf
          ? BoxDecoration(
              color: colors.selectionFill,
              borderRadius: BorderRadius.circular(10),
            )
          : null,
      child: Row(
        children: [
          RAvatar(name: name, size: 30),
          SizedBox(width: context.spacing.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                if (isPayer) ...[
                  const SizedBox(height: 1),
                  Text(
                    context.l10n.editorPaidRole,
                    style: AppTypography.sans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.primaryDark,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Wrapped LTR so the amount can't bidi-reorder in Arabic (#151).
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              AppFormatters.formatCurrency(share, currency),
              maxLines: 1,
              softWrap: false,
              style: AppTypography.mono(
                fontSize: 14,
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReconcileFooter extends StatelessWidget {
  const _ReconcileFooter({required this.descriptor, required this.addsUpTo});

  final Widget descriptor;
  final String addsUpTo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.success.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          descriptor,
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.check_rounded, size: 14, color: colors.successText),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  addsUpTo,
                  style: AppTypography.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.successText,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
