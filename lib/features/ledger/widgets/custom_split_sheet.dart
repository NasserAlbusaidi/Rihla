import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/models/split_mode.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/services/money_serializer.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/localized_decimal_input.dart';
import '../../../core/utils/split_mode_display_name.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../models/expense_model.dart' show ExpenseScope;
import '../models/split_explanation.dart';
import '../providers/expense_provider.dart' show BalanceCalculator;

export '../../../core/models/split_mode.dart' show SplitMode;

// Itemized split tab widgets + the per-row draft model (#203 S2). Kept in a
// sibling `part` so this file holds the sheet state/logic and stays readable.
part 'custom_split_sheet_itemized.dart';
part 'custom_split_sheet_chrome.dart';
part 'custom_split_sheet_mode_selector.dart';
part 'custom_split_sheet_editors.dart';

/// Result returned by [showCustomSplitSheet]. `distribution` is null when
/// [mode] is [SplitMode.equally] — the legacy equal split path in
/// `BalanceCalculator` handles that case, so we deliberately do NOT persist a
/// distribution map for it.
class SplitResult {
  const SplitResult({
    required this.mode,
    required this.distribution,
    this.items,
    this.adjustments,
  });

  final SplitMode mode;
  final Map<String, Decimal>? distribution;

  /// Non-null ONLY for an itemized result (#203 S2, produced by PR2's editor).
  /// When set, [mode] is always [SplitMode.exact] and [distribution] is
  /// `allocateItemizedDistribution(items, adjustments)`. Null for every plain
  /// mode, so the existing four-arm paths return `items: null` and persist no
  /// metadata.
  final List<SplitItem>? items;

  /// Bill-level adjustments (#605), non-null only alongside [items] (itemized).
  /// May be empty (itemized with no adjustments). Folded into [distribution];
  /// ride along as display metadata in `splitExplanation.adjustments`.
  final List<SplitAdjustment>? adjustments;
}

/// Bottom-sheet split editor. Supports four modes:
///   - [SplitMode.equally]: read-only equal share preview.
///   - [SplitMode.shares]: integer stepper per participant (weighted).
///   - [SplitMode.exact]: per-participant exact amount inputs; sum must
///     match [total] within 0.001.
///   - [SplitMode.percent]: per-participant percent inputs; sum must reach
///     100 within 0.001.
///
/// Returns `null` on cancel/dismiss, or a [SplitResult] when Apply is tapped.
///
/// [initialItemized] opens directly on the Itemized tab (#203 S2) seeded from
/// [initialItems] — used to reconstruct an itemized split on reopen. When
/// itemized, [initialMode]/[initialDistribution] are ignored (the tab owns its
/// own draft state).
Future<SplitResult?> showCustomSplitSheet(
  BuildContext context, {
  required String title,
  required Decimal total,
  required String currency,
  required List<SplitParticipant> participants,
  SplitMode initialMode = SplitMode.equally,
  Map<String, Decimal>? initialDistribution,
  List<SplitItem>? initialItems,
  List<SplitAdjustment>? initialAdjustments,
  bool initialItemized = false,
}) {
  return showModalBottomSheet<SplitResult>(
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
      initialMode: initialMode,
      initialDistribution: initialDistribution,
      initialItems: initialItems,
      initialAdjustments: initialAdjustments,
      initialItemized: initialItemized,
    ),
  );
}

/// Sealed outcome of an itemized fold attempt (#605): the per-person
/// distribution plus whether an assigned discount overshot its subset. Emitted
/// by `_computeItemizedFold` and consumed by preview / Apply-gate / build.
class _ItemizedFold {
  const _ItemizedFold(this.distribution, {this.assignedOvershoot = false});

  final Map<String, Decimal> distribution;
  final bool assignedOvershoot;

  bool get ok => !assignedOvershoot;
}

class SplitParticipant {
  const SplitParticipant({
    required this.id,
    required this.name,
    this.role,
    this.isShadow = false,
  });

  final String id;
  final String name;

  /// Optional small caption shown next to the name (e.g. "You", "Paid").
  final String? role;

  /// True for a placeholder ("shadow") member added by name but not yet
  /// joined (#278) — surfaced with a "not joined yet" marker. Display only.
  final bool isShadow;
}

class CustomSplitSheet extends StatefulWidget {
  const CustomSplitSheet({
    super.key,
    required this.title,
    required this.total,
    required this.currency,
    required this.participants,
    this.initialMode = SplitMode.equally,
    this.initialDistribution,
    this.initialItems,
    this.initialAdjustments,
    this.initialItemized = false,
  });

  final String title;
  final Decimal total;
  final String currency;
  final List<SplitParticipant> participants;
  final SplitMode initialMode;
  final Map<String, Decimal>? initialDistribution;

  /// Line items to seed the Itemized tab with (#203 S2) — non-null only when
  /// reopening an itemized expense. Each row's amount is shown via
  /// [MoneySerializer.fromSubunits] in [currency].
  final List<SplitItem>? initialItems;

  /// Bill-level adjustments to seed (#605) — non-null only when reopening an
  /// itemized expense that carried adjustments.
  final List<SplitAdjustment>? initialAdjustments;

  /// Open directly on the Itemized tab (#203 S2). When true the sheet builds
  /// its draft rows from [initialItems] (or one empty row if null).
  final bool initialItemized;

  @override
  State<CustomSplitSheet> createState() => _CustomSplitSheetState();
}

class _CustomSplitSheetState extends State<CustomSplitSheet> {
  static final Decimal _tolerance = Decimal.parse('0.001');
  static final Decimal _hundred = Decimal.fromInt(100);

  late SplitMode _mode;

  /// Itemized is NOT a [SplitMode] (#203 S2) — it persists AS exact. When true
  /// the body renders the [_ItemizedBody] and Apply emits the allocator's exact
  /// distribution; [_mode] still holds the last real mode for switching back.
  late bool _itemized;

  // Per-mode state. Each map is keyed by participant id.
  late Map<String, int> _shares;
  late Map<String, TextEditingController> _exactCtrls;
  late Map<String, TextEditingController> _percentCtrls;

  /// Itemized line-item drafts. Owned here so controllers are disposed once.
  late List<_ItemDraft> _drafts;

  /// Bill-level adjustment drafts (#605). Owned here; controllers disposed once.
  late List<_AdjustmentDraft> _adjDrafts;

  // Drafts pruned while their editor sheet is still animating closed: the
  // sheet's TextField rebuilds during the exit transition and re-subscribes
  // to `amount`, so disposing now throws "used after being disposed" (#1049).
  // Held here and disposed in dispose() when the whole sheet tears down.
  final List<_AdjustmentDraft> _retiredAdjDrafts = [];

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _itemized = widget.initialItemized;
    _initShares();
    _initExact();
    _initPercent();
    _initDrafts();
    _initAdjustmentDrafts();
  }

  @override
  void dispose() {
    for (final c in _exactCtrls.values) {
      c.dispose();
    }
    for (final c in _percentCtrls.values) {
      c.dispose();
    }
    for (final d in _drafts) {
      d.dispose();
    }
    for (final d in _adjDrafts) {
      d.dispose();
    }
    for (final d in _retiredAdjDrafts) {
      d.dispose();
    }
    super.dispose();
  }

  void _initDrafts() {
    final seed = widget.initialItems;
    if (widget.initialItemized && seed != null && seed.isNotEmpty) {
      _drafts = [for (final item in seed) _ItemDraft.fromItem(item, widget.currency)];
    } else {
      _drafts = [_ItemDraft.empty()];
    }
  }

  void _initAdjustmentDrafts() {
    final seed = widget.initialAdjustments;
    _adjDrafts = (widget.initialItemized && seed != null)
        ? [for (final a in seed) _AdjustmentDraft.fromAdjustment(a, widget.currency)]
        : <_AdjustmentDraft>[];
  }

  void _addDraft() {
    setState(() => _drafts.add(_ItemDraft.empty()));
  }

  void _removeDraft(_ItemDraft draft) {
    if (_drafts.length <= 1) return;
    setState(() {
      _drafts.remove(draft);
    });
    draft.dispose();
  }

  /// "+ Add" an adjustment: append an empty draft and open the editor on it.
  /// On close, an unfilled draft is pruned (so it never blocks Apply or persists).
  void _addAdjustment() {
    final draft = _AdjustmentDraft.empty();
    setState(() => _adjDrafts.add(draft));
    _openAdjustmentEditor(draft);
  }

  Future<void> _openAdjustmentEditor(_AdjustmentDraft draft) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.scaffoldBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddAdjustmentSheet(
        draft: draft,
        participants: widget.participants,
        currency: widget.currency,
      ),
    );
    if (!mounted) return;
    setState(() {
      // Blank/invalid on close ⇒ discard (also the "clear to delete" path on edit).
      if (!_adjValid(draft)) {
        _adjDrafts.remove(draft);
        _retiredAdjDrafts.add(draft); // dispose deferred to dispose() — see field doc (#1049)
      }
    });
  }

  void _removeAdjustment(_AdjustmentDraft draft) {
    setState(() => _adjDrafts.remove(draft));
    // Safe to dispose immediately (unlike the editor's prune path, #1049): the
    // row is inline in this sheet, so it unmounts in the same synchronous
    // rebuild — no lingering modal exit-transition frame re-touches `amount`.
    // Keep this true if rows ever move into a Dismissible/AnimatedList.
    draft.dispose();
  }

  void _initShares() {
    _shares = {
      for (final p in widget.participants) p.id: _readInitialShare(p.id) ?? 1,
    };
  }

  void _initExact() {
    _exactCtrls = {
      for (final p in widget.participants)
        p.id: TextEditingController(text: _readInitialExact(p.id)),
    };
    if (widget.initialMode == SplitMode.exact) {
      _seedExactIfBlank();
    }
  }

  void _initPercent() {
    _percentCtrls = {
      for (final p in widget.participants)
        p.id: TextEditingController(text: _readInitialPercent(p.id)),
    };
    if (widget.initialMode == SplitMode.percent) {
      _seedPercentIfBlank();
    }
  }

  bool _controllersAllBlank(Map<String, TextEditingController> controllers) =>
      controllers.values.every((c) => c.text.trim().isEmpty);

  void _seedExactIfBlank() {
    if (!_controllersAllBlank(_exactCtrls)) return;
    final Map<String, Decimal> seed = BalanceCalculator.allocateExpenseOwed(
      amount: widget.total,
      splitMode: SplitMode.equally,
      splitDistribution: null,
      scope: ExpenseScope.global,
      customSplitParticipants: null,
      payerId: '',
      participantIds: _participantIds,
      currency: widget.currency,
      onFallback: null,
    );
    for (final entry in _exactCtrls.entries) {
      final value = seed[entry.key];
      if (value == null) continue;
      entry.value.text = _formatPlainDecimal(value);
    }
  }

  void _seedPercentIfBlank() {
    if (!_controllersAllBlank(_percentCtrls)) return;
    final ids = _participantIds..sort();
    final count = ids.length;
    if (count == 0) return;

    final base = (_hundred / Decimal.fromInt(count)).toDecimal(
      scaleOnInfinitePrecision: 3,
    );
    final lastId = ids.last;
    final lastValue = _hundred - (base * Decimal.fromInt(count - 1));

    for (final entry in _percentCtrls.entries) {
      final value = entry.key == lastId ? lastValue : base;
      entry.value.text = _formatPlainDecimal(value);
    }
  }

  int? _readInitialShare(String id) {
    if (widget.initialMode != SplitMode.shares) return null;
    final v = widget.initialDistribution?[id];
    if (v == null) return null;
    return v.toBigInt().toInt();
  }

  String _readInitialExact(String id) {
    if (widget.initialMode != SplitMode.exact) return '';
    final v = widget.initialDistribution?[id];
    if (v == null) return '';
    return _formatPlainDecimal(v);
  }

  String _readInitialPercent(String id) {
    if (widget.initialMode != SplitMode.percent) return '';
    final v = widget.initialDistribution?[id];
    if (v == null) return '';
    return _formatPlainDecimal(v);
  }

  static String _formatPlainDecimal(Decimal v) {
    final s = v.toString();
    if (!s.contains('.')) return s;
    // Trim trailing zeros so "1.000" → "1" and "12.500" → "12.5".
    var trimmed = s.replaceFirst(RegExp(r'0+$'), '');
    if (trimmed.endsWith('.')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  // ───────────────────────────────────────────────────── live computations

  Decimal get _exactSum {
    var sum = Decimal.zero;
    for (final c in _exactCtrls.values) {
      final v = Decimal.tryParse(c.text);
      if (v != null) sum += v;
    }
    return sum;
  }

  Decimal get _percentSum {
    var sum = Decimal.zero;
    for (final c in _percentCtrls.values) {
      final v = Decimal.tryParse(c.text);
      if (v != null) sum += v;
    }
    return sum;
  }

  int get _totalShares => _shares.values.fold(0, (acc, v) => acc + v);

  Decimal get _exactRemainder => widget.total - _exactSum;

  Decimal get _percentRemainder => _hundred - _percentSum;

  // ─────────────────────────────────────────────────── itemized (#203 S2)

  /// Parsed amount for a draft, or null if blank/unparseable/non-positive.
  Decimal? _draftAmount(_ItemDraft d) {
    final v = Decimal.tryParse(d.amount.text);
    if (v == null || v <= Decimal.zero) return null;
    return v;
  }

  /// A draft is allocatable when it has a positive amount AND ≥1 assignee —
  /// exactly the allocator's precondition (it throws otherwise).
  bool _draftValid(_ItemDraft d) =>
      _draftAmount(d) != null && d.assignees.isNotEmpty;

  Decimal get _itemizedSum {
    var sum = Decimal.zero;
    for (final d in _drafts) {
      sum += _draftAmount(d) ?? Decimal.zero;
    }
    return sum;
  }

  // ───────────────────────────────────────────── bill-level adjustments (#605)

  /// Parsed amount for an adjustment draft, or null if blank/unparseable/≤0.
  Decimal? _adjAmount(_AdjustmentDraft d) {
    final v = Decimal.tryParse(d.amount.text);
    if (v == null || v <= Decimal.zero) return null;
    return v;
  }

  bool _adjValid(_AdjustmentDraft d) => _adjAmount(d) != null;

  Decimal get _adjAdditiveSum {
    var sum = Decimal.zero;
    for (final d in _adjDrafts) {
      if (d.type != 'discount') sum += _adjAmount(d) ?? Decimal.zero;
    }
    return sum;
  }

  Decimal get _adjDiscountSum {
    var sum = Decimal.zero;
    for (final d in _adjDrafts) {
      if (d.type == 'discount') sum += _adjAmount(d) ?? Decimal.zero;
    }
    return sum;
  }

  /// The folded subtotal the bill must reconcile to: items + additive − discount.
  Decimal get _itemizedFoldedSum =>
      _itemizedSum + _adjAdditiveSum - _adjDiscountSum;

  Decimal get _itemizedRemainder => widget.total - _itemizedFoldedSum;

  List<String> get _participantIds => [for (final p in widget.participants) p.id];

  /// Single chokepoint (#605) that attempts the full itemized fold for the
  /// current drafts and returns a sealed [_ItemizedFold] — the distribution
  /// PLUS whether an assigned discount overshot its subset. `_itemizedPreview`,
  /// `_itemizedCanApply`, and `_buildItemizedResult` ALL read this, so build
  /// never throws, Apply disables coherently, and the preview never flashes
  /// misleading zeros. The allocator's throw is the authoritative subset check
  /// (the sequential fold makes per-subset owed state-dependent) — the subset
  /// math is NEVER duplicated here.
  ///
  /// Two overshoot regimes, deliberately different (spec-pinned):
  ///  - ASSIGNED-subset overshoot → error state (Apply disabled, inline error);
  ///    the preview degrades to the pre-assigned-discount fold (items +
  ///    additive), never zeroed.
  ///  - POOLED whole-bill overshoot → graceful DEGRADE (drop the pooled
  ///    discounts, keep items rendering while a discount is typed) — the
  ///    pre-existing #605 behavior, no error state.
  _ItemizedFold _computeItemizedFold() {
    final items = [
      for (final d in _drafts)
        if (_draftValid(d)) d.toItem(widget.currency),
    ];
    final validAdj = [for (final d in _adjDrafts) if (_adjValid(d)) d];
    if (items.isEmpty && validAdj.isEmpty) return const _ItemizedFold({});

    // Normalize once (the OUTBOUND point): an 'assigned' discount with no
    // chosen members has already degraded to 'proportional' in toAdjustment.
    final normalized = [for (final d in validAdj) d.toAdjustment(widget.currency)];
    final additive = [for (final a in normalized) if (a.type != 'discount') a];
    final assigned = [
      for (final a in normalized)
        if (a.type == 'discount' && a.allocation == 'assigned') a,
    ];
    final pooled = [
      for (final a in normalized)
        if (a.type == 'discount' && a.allocation != 'assigned') a,
    ];

    // Step 1 — items + additive + assigned discounts.
    Map<String, Decimal> base;
    try {
      base = _foldOrEmpty(items, [...additive, ...assigned]);
    } on ArgumentError {
      // Assigned-subset overshoot → error; preview the pre-assigned fold.
      return _ItemizedFold(_foldOrEmpty(items, additive), assignedOvershoot: true);
    }

    // Step 2 — pooled discounts, proportional to the post-assigned state.
    if (pooled.isEmpty) return _ItemizedFold(base);
    try {
      return _ItemizedFold(_foldOrEmpty(items, [...additive, ...assigned, ...pooled]));
    } on ArgumentError {
      // Pooled whole-bill overshoot → degrade (keep items rendering).
      return _ItemizedFold(base);
    }
  }

  /// Fold helper: empty in / empty out (the allocator requires a non-empty
  /// participant table only when adjustments are present).
  Map<String, Decimal> _foldOrEmpty(
    List<SplitItem> items,
    List<SplitAdjustment> adjustments,
  ) {
    if (items.isEmpty && adjustments.isEmpty) return const {};
    return BalanceCalculator.allocateItemizedDistribution(
      items: items,
      currency: widget.currency,
      adjustments: adjustments,
      participantIds: _participantIds,
    );
  }

  bool get _itemizedCanApply {
    if (widget.participants.isEmpty) return false;
    if (_drafts.isEmpty) return false;
    if (!_drafts.every(_draftValid)) return false;
    if (!_adjDrafts.every(_adjValid)) return false;
    // An assigned-discount subset overshoot blocks Apply even if the bill-level
    // remainder reconciles (the fold is the authoritative subset check).
    if (!_computeItemizedFold().ok) return false;
    return _itemizedRemainder.abs() <= _tolerance;
  }

  bool get _canApply {
    if (widget.participants.isEmpty) return false;
    if (_itemized) return _itemizedCanApply;
    switch (_mode) {
      case SplitMode.equally:
        return true;
      case SplitMode.shares:
        return _totalShares > 0;
      case SplitMode.exact:
        return _exactRemainder.abs() <= _tolerance;
      case SplitMode.percent:
        return _percentRemainder.abs() <= _tolerance;
    }
  }

  // ───────────────────────────────────────────────────── apply

  void _apply() {
    HapticService.medium();
    final result = _buildResult();
    Navigator.of(context).pop(result);
  }

  SplitResult _buildResult() {
    if (_itemized) return _buildItemizedResult();
    switch (_mode) {
      case SplitMode.equally:
        return const SplitResult(mode: SplitMode.equally, distribution: null);
      case SplitMode.shares:
        return SplitResult(
          mode: SplitMode.shares,
          distribution: {
            for (final p in widget.participants)
              p.id: Decimal.fromInt(_shares[p.id] ?? 0),
          },
        );
      case SplitMode.exact:
        return SplitResult(
          mode: SplitMode.exact,
          distribution: {
            for (final p in widget.participants)
              p.id:
                  Decimal.tryParse(_exactCtrls[p.id]?.text ?? '') ??
                  Decimal.zero,
          },
        );
      case SplitMode.percent:
        return SplitResult(
          mode: SplitMode.percent,
          distribution: {
            for (final p in widget.participants)
              p.id:
                  Decimal.tryParse(_percentCtrls[p.id]?.text ?? '') ??
                  Decimal.zero,
          },
        );
    }
  }

  /// Build the itemized result (#203 S2 / #605): every draft is valid here
  /// (Apply is gated on [_itemizedCanApply], which requires a clean fold), so
  /// the distribution comes from the same [_computeItemizedFold] chokepoint —
  /// never a second, drifting allocator call. Itemized persists AS
  /// [SplitMode.exact]; items + adjustments ride along as display metadata.
  SplitResult _buildItemizedResult() {
    final items = [for (final d in _drafts) d.toItem(widget.currency)];
    final adjustments = [
      for (final d in _adjDrafts) d.toAdjustment(widget.currency),
    ];
    return SplitResult(
      mode: SplitMode.exact,
      distribution: _computeItemizedFold().distribution,
      items: items,
      adjustments: adjustments,
    );
  }

  // ───────────────────────────────────────────────────── build

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    // Compute the itemized fold ONCE per build (#605) — preview + error flag
    // read the same sealed result.
    final itemizedFold = _itemized ? _computeItemizedFold() : null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
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
            _Header(
              title: widget.title,
              total: widget.total,
              currency: widget.currency,
            ),
            SizedBox(height: spacing.space16),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.space24),
              child: _ModeSegmented(
                itemized: _itemized,
                mode: _mode,
                onMode: (next) {
                  HapticService.selection();
                  setState(() {
                    _mode = next;
                    _itemized = false;
                    if (next == SplitMode.exact) {
                      _seedExactIfBlank();
                    } else if (next == SplitMode.percent) {
                      _seedPercentIfBlank();
                    }
                  });
                },
                onItemized: () {
                  HapticService.selection();
                  setState(() => _itemized = true);
                },
              ),
            ),
            SizedBox(height: spacing.space16),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: spacing.space24),
                child: _itemized
                    ? _ItemizedBody(
                        key: const ValueKey('itemized'),
                        drafts: _drafts,
                        adjDrafts: _adjDrafts,
                        participants: widget.participants,
                        currency: widget.currency,
                        preview: itemizedFold!.distribution,
                        assignedDiscountError: itemizedFold.assignedOvershoot,
                        draftValid: _draftValid,
                        onChanged: () => setState(() {}),
                        onAddItem: _addDraft,
                        onRemoveItem: _removeDraft,
                        onAddAdjustment: _addAdjustment,
                        onEditAdjustment: _openAdjustmentEditor,
                        onRemoveAdjustment: _removeAdjustment,
                      )
                    : _ModeBody(
                        key: ValueKey(_mode),
                        mode: _mode,
                        participants: widget.participants,
                        total: widget.total,
                        currency: widget.currency,
                        shares: _shares,
                        exactCtrls: _exactCtrls,
                        percentCtrls: _percentCtrls,
                        totalShares: _totalShares,
                        onSharesChanged: () => setState(() {}),
                        onAmountChanged: () => setState(() {}),
                      ),
              ),
            ),
            _Footer(
              itemized: _itemized,
              mode: _mode,
              total: widget.total,
              currency: widget.currency,
              exactSum: _exactSum,
              exactRemainder: _exactRemainder,
              percentSum: _percentSum,
              percentRemainder: _percentRemainder,
              itemizedSum: _itemizedFoldedSum,
              itemizedRemainder: _itemizedRemainder,
              canApply: _canApply,
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.space24,
                0,
                spacing.space24,
                spacing.space20,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: colors.rule2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          context.l10n.customSplitCancel,
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
                        key: const Key('split_sheet_apply'),
                        onPressed: _canApply ? _apply : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primary,
                          foregroundColor: colors.textOnPrimary,
                          disabledBackgroundColor: colors.primary.withValues(
                            alpha: 0.35,
                          ),
                          disabledForegroundColor: colors.textOnPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          context.l10n.customSplitApply,
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
      ),
    );
  }
}
