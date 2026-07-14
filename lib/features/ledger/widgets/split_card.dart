import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/models/split_mode.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../events/models/event_model.dart';
import '../../groups/services/member_name_resolver.dart';
import '../models/expense_model.dart';
import '../models/split_explanation.dart';
import '../providers/expense_provider.dart';
import 'split_card/field_label.dart';
import 'split_card/mode_segment.dart';
import 'split_card/payer_inline_row.dart';
import 'split_card/reconcile_footer.dart';
import 'split_card/scope_segment.dart';
import 'split_card/split_person_row.dart';
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
    this.eligiblePickerIds,
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

  /// #1149: NEW-expense candidate allow-list forwarded to the custom
  /// participant selector (active, non-tombstone members; already-selected ids
  /// retained downstream). Null → no filtering. The equal-split PREVIEW is
  /// deliberately NOT filtered — it is money display, not a candidate list.
  final Set<String>? eligiblePickerIds;

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
            FieldLabel(l10n.editorPaidBy),
            const SizedBox(height: 8),
            PayerInlineRow(
              name: payerName,
              colorKey: payerId,
              onChange: widget.onChangePayer,
            ),

            const SizedBox(height: 18),

            // ── Who splits — plain-language scope ────────────────────────
            Row(
              children: [
                Expanded(child: FieldLabel(l10n.editorWhoSplits)),
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
            ScopeSegment(scope: widget.scope, onChanged: widget.onScopeChanged),
            if (widget.scope == ExpenseScope.custom) ...[
              const SizedBox(height: 14),
              CustomParticipantSelector(
                event: widget.event,
                customSplitParticipants: widget.customSplitParticipants,
                eligibleIds: widget.eligiblePickerIds,
                onCustomSplitChanged: widget.onCustomSplitChanged,
              ),
            ],

            const SizedBox(height: 18),

            // ── How — split mode ─────────────────────────────────────────
            FieldLabel(l10n.editorHow),
            const SizedBox(height: 8),
            ModeSegment(
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
              ReconcileFooter(
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
    return SplitPersonRow(
      name: name,
      colorKey: id,
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

