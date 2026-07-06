import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart' show mapEquals, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/services/money_serializer.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/error_message_translator.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/localized_decimal_input.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../events/models/event_model.dart';
import '../../events/providers/event_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../../groups/services/member_name_resolver.dart';
import '../../groups/widgets/currency_picker_sheet.dart';
import '../../home/widgets/add_expense_target_sheet.dart';
import '../../trip/providers/trip_provider.dart';
import '../keys/ledger_keys.dart';
import '../models/expense_model.dart';
import '../models/split_explanation.dart';
import '../providers/category_provider.dart';
import 'custom_split_sheet.dart';
import 'expense_editor/amount_hero.dart';
import 'expense_editor/category_strip.dart';
import 'expense_editor/currency_mismatch_notice.dart';
import 'expense_editor/currency_row.dart';
import 'expense_editor/delete_card.dart';
import 'expense_editor/description_field.dart';
import 'expense_editor/editor_section.dart';
import 'expense_editor/expense_provenance_byline.dart';
import 'expense_editor/expense_top_bar.dart';
import 'expense_editor/payer_picker_sheet.dart';
import 'expense_editor/where_card.dart';
import 'split_card.dart';

enum ExpenseEditorMode { add, edit }

/// Seeds the custom-split set with the current participant the first time the
/// user switches into custom scope, so a custom split defaults to "just me"
/// (deselectable). Returns [current] unchanged when the new scope is not
/// custom, when the set is already non-empty, or when identity is unknown — so
/// custom→global→custom never re-seeds and editing an existing split is
/// preserved (#247).
@visibleForTesting
Set<String> seedCustomSplitOnScopeChange({
  required ExpenseScope newScope,
  required Set<String> current,
  required String? currentParticipantId,
}) {
  if (newScope != ExpenseScope.custom) return current;
  if (current.isNotEmpty) return current;
  if (currentParticipantId == null) return current;
  return {currentParticipantId};
}

/// Snapshot of the form payload handed back to the parent on submit.
class ExpenseEditorPayload {
  final Decimal amount;
  final String? description;
  final ExpenseScope scope;
  final String? categoryId;
  final String payerParticipantId;
  final List<String>? customSplitParticipants;
  final SplitMode splitMode;

  /// When [splitMode] is [SplitMode.equally] this is null and the parent
  /// must NOT persist any distribution. For non-equal modes this is the
  /// per-participant weight/amount/percent.
  final Map<String, Decimal>? splitDistribution;

  /// The ISO code the expense is denominated in (#382 PR-6). In add mode this
  /// is the user's picked currency (smart default = last-used / group default);
  /// in edit mode it equals the expense's stored currency. The host scales
  /// `amountFils` by this code, so it must reach the write.
  final String currency;

  /// Itemized display metadata (#203 S2). Non-null ⇒ [splitMode] is exact and
  /// the distribution came from `allocateItemizedDistribution`. Null for every
  /// other mode (and always null until PR2 wires the itemized editor).
  final SplitExplanation? splitExplanation;

  const ExpenseEditorPayload({
    required this.amount,
    required this.description,
    required this.scope,
    required this.categoryId,
    required this.payerParticipantId,
    required this.customSplitParticipants,
    required this.splitMode,
    required this.splitDistribution,
    required this.currency,
    required this.splitExplanation,
  });
}

/// Shared single-page expense form used by both Add and Edit screens.
///
/// Matches the `Hi_AddExpense` / `Hi_EditExpense` wireframes:
/// - Edit mode is the same form with title "Edit expense", trailing "Save",
///   and a soft delete card at the bottom.
class ExpenseEditorBody extends ConsumerStatefulWidget {
  final String groupId;
  final String eventId;
  final ExpenseEditorMode mode;

  /// The currency the expense is denominated in. In add mode this carries the
  /// smart default (last-used-in-event → group default, #382 PR-6) and seeds the
  /// picker; in edit mode it's the expense's own stored currency. Threaded by
  /// the parent — the body never defaults it (a silent 'OMR' would mis-scale a
  /// non-OMR group 10×).
  final String currency;

  /// The event's dominant (most-frequent) currency, used only to drive the soft
  /// fat-finger warning in add mode (#382 PR-6). Null while the event's expenses
  /// are still loading or in edit mode → no warning.
  final String? dominantCurrency;

  /// Pre-fill values (edit mode only).
  final Expense? initial;

  /// Called when the user taps Add/Save with a valid payload. Should throw on
  /// failure — the body surfaces a snackbar with the error message.
  final Future<void> Function(ExpenseEditorPayload payload) onSubmit;

  /// Called when the user confirms deletion. Edit mode only.
  final Future<void> Function()? onDelete;

  const ExpenseEditorBody({
    super.key,
    required this.groupId,
    required this.eventId,
    required this.mode,
    required this.currency,
    required this.onSubmit,
    this.dominantCurrency,
    this.initial,
    this.onDelete,
  }) : assert(
         mode == ExpenseEditorMode.add || initial != null,
         'Edit mode requires an initial expense',
       );

  @override
  ConsumerState<ExpenseEditorBody> createState() => _ExpenseEditorBodyState();
}

class _ExpenseEditorBodyState extends ConsumerState<ExpenseEditorBody> {
  late final TextEditingController _noteController;
  late final TextEditingController _amountController;
  late final FocusNode _amountFocusNode;

  late String _amount;
  late ExpenseScope _scope;
  String? _selectedCategoryId;

  /// #204: set when a save is attempted with no category picked (category is
  /// mandatory at creation). Drives the inline "choose a category" hint; cleared
  /// the moment the user selects one.
  bool _categoryError = false;
  String? _selectedPayerId;
  late Set<String> _customSplitParticipants;

  /// The ISO code the (add-mode) user has chosen for this expense (#382 PR-6).
  /// Seeded from [widget.currency] (the smart default) and re-seeded by
  /// [didUpdateWidget] until the user picks manually. Unused in edit mode —
  /// [effectiveCurrency] returns [widget.currency] there.
  late String _selectedCurrency;

  /// True once the user taps the currency row, freezing [_selectedCurrency]
  /// against a late-arriving smart default (so a manual pick is never clobbered).
  bool _currencyManuallyPicked = false;

  /// How the expense total is divided. Defaults to [SplitMode.equally] in add
  /// mode and to whatever the existing expense stored in edit mode.
  late SplitMode _splitMode;

  /// Per-participant weights/amounts/percents keyed by participant id.
  /// Null when [_splitMode] is [SplitMode.equally] — the balance calculator
  /// handles equal splits without a distribution map.
  Map<String, Decimal>? _splitDistribution;

  /// Itemized display metadata (#203 S2). Non-null only for an itemized split
  /// (PR2 sets it from the "How" sheet); round-trips the original in edit mode.
  /// There is no UI to set it yet, so it stays null in add mode.
  SplitExplanation? _splitExplanation;

  /// Write-time split-vs-amount tolerance — mirrors custom_split_sheet._tolerance
  /// and BalanceCalculator._splitTolerance (the same 0.001 contract). (#250)
  static final Decimal _splitTolerance = Decimal.parse('0.001');

  bool _isSubmitting = false;

  // --- Discard guard (#818 Wave 3.2) -------------------------------------
  // Snapshot of the form at open. `_isDirty` compares the CURRENT working
  // fields against these, frozen once in initState — see the class doc below
  // each field for why re-deriving from widget.initial/providers would be
  // wrong (a mid-session settings change or a remote open-edit swap must not
  // retroactively change what counts as "the user's own edits").
  late final String _pristineAmount;
  late final String _pristineNote;
  late final ExpenseScope _pristineScope;
  late final String? _pristineCategoryId;
  late final String? _pristinePayerId;
  late final Set<String> _pristineCustomSplit;
  late final SplitMode _pristineSplitMode;
  late final Map<String, Decimal>? _pristineSplitDistribution;
  late final SplitExplanation? _pristineSplitExplanation;

  /// True once the working form state has diverged from the pristine
  /// baseline captured at open. Drives `PopScope.canPop` and the X button.
  /// Currency dirtiness is `_currencyManuallyPicked` (add-mode only) rather
  /// than a value compare — the #382 PR-6 async smart default re-seeds
  /// [_selectedCurrency] via [didUpdateWidget] without user action, and that
  /// must never false-dirty a pristine screen.
  bool get _isDirty =>
      _amount != _pristineAmount ||
      _noteController.text != _pristineNote ||
      _scope != _pristineScope ||
      _selectedCategoryId != _pristineCategoryId ||
      _selectedPayerId != _pristinePayerId ||
      !setEquals(_customSplitParticipants, _pristineCustomSplit) ||
      _splitMode != _pristineSplitMode ||
      !mapEquals(_splitDistribution, _pristineSplitDistribution) ||
      !identical(_splitExplanation, _pristineSplitExplanation) ||
      (!_isEdit && _currencyManuallyPicked);

  /// #627 follow-up: the disambiguation name map is event-derived and shared by
  /// every in-build consumer (`_PaidByCard`, `ExpenseProvenanceByline`,
  /// `_SplitPreviewCard`). The parent `setState`s `_amount` on every keystroke,
  /// so `build` re-runs per digit; without this memo each consumer would re-run
  /// `disambiguateEventParticipants` on every keystroke. Cached here and
  /// recomputed only when the event INSTANCE changes — see [_disambiguatedNames].
  Event? _displayNamesKey;
  Map<String, String> _displayNames = const {};

  bool get _isEdit => widget.mode == ExpenseEditorMode.edit;

  /// The currency every money surface in the editor scales/labels with (#382
  /// PR-6). Edit mode is immutable (the stored currency); add mode follows the
  /// picker. EVERY consumer of the denominating currency must read this, not
  /// [widget.currency] — the amount hero, the input-decimal clamp, and any
  /// exact-split entry/preview, or the picked scale silently diverges from the
  /// persisted one.
  String get effectiveCurrency => _isEdit ? widget.currency : _selectedCurrency;

  @override
  void initState() {
    super.initState();
    _selectedCurrency = widget.currency;
    final initial = widget.initial;
    if (initial != null) {
      _amount = initial.amount.toString();
      _amountController = TextEditingController(text: _amount);
      _amountFocusNode = FocusNode();
      _noteController = TextEditingController(text: initial.description ?? '');
      _scope = initial.scope;
      _selectedCategoryId = initial.categoryId;
      _selectedPayerId = initial.payerParticipantId;
      _customSplitParticipants =
          initial.customSplitParticipants?.toSet() ?? <String>{};
      _splitMode = initial.splitMode ?? SplitMode.equally;
      _splitDistribution = initial.splitDistribution == null
          ? null
          : Map<String, Decimal>.from(initial.splitDistribution!);
      _splitExplanation = initial.splitExplanation;
    } else {
      _amount = '0';
      _amountController = TextEditingController(text: '0');
      _amountFocusNode = FocusNode();
      _noteController = TextEditingController();
      _scope = ExpenseScope.global;
      _customSplitParticipants = <String>{};
      _splitMode = ref.read(settingsProvider).defaultSplitMode;
      _splitDistribution = null;
      _splitExplanation = null;
    }
    _amountFocusNode.addListener(_selectDefaultZeroOnFocus);
    // #818 Wave 3.2: the note field's own setState (_DescriptionFieldState,
    // for its inline validation) is local to that child — the parent's
    // canPop must be told about note-only edits too, or a stale `true`
    // survives a system-back check (amount already rebuilds the parent via
    // its onChanged setState).
    _noteController.addListener(_onNoteChanged);

    // Pristine baseline — captured AFTER both mode branches above so it's an
    // exact snapshot of what was just assigned. The Set/Map are defensive
    // copies (Gate r1 [P2]): every current mutation is replace-only, but a
    // shared reference would let a future in-place mutation silently mutate
    // the baseline too, making the dirty predicate read clean forever.
    _pristineAmount = _amount;
    _pristineNote = _noteController.text;
    _pristineScope = _scope;
    _pristineCategoryId = _selectedCategoryId;
    _pristinePayerId = _selectedPayerId;
    _pristineCustomSplit = Set.of(_customSplitParticipants);
    _pristineSplitMode = _splitMode;
    _pristineSplitDistribution = _splitDistribution == null
        ? null
        : Map.of(_splitDistribution!);
    _pristineSplitExplanation = _splitExplanation;
  }

  void _onNoteChanged() => setState(() {});

  @override
  void didUpdateWidget(covariant ExpenseEditorBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // #382 PR-6: the parent computes the smart default asynchronously (from the
    // event's expense history) and may hand it down AFTER the first frame. Adopt
    // the late default as long as the user hasn't picked manually — so the form
    // never gates on the history yet still lands on last-used-in-event.
    if (!_isEdit &&
        !_currencyManuallyPicked &&
        widget.currency != oldWidget.currency) {
      _selectedCurrency = widget.currency;
    }
  }

  @override
  void dispose() {
    _amountFocusNode.removeListener(_selectDefaultZeroOnFocus);
    _amountFocusNode.dispose();
    _noteController.removeListener(_onNoteChanged);
    _noteController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _selectDefaultZeroOnFocus() {
    if (!_amountFocusNode.hasFocus) return;
    _queueSelectDefaultZero();
  }

  void _queueSelectDefaultZero() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_amountFocusNode.hasFocus) return;
      if (_amountController.text != '0') return;
      _amountController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _amountController.text.length,
      );
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    Decimal amount;
    try {
      amount = Decimal.parse(_amount);
    } on FormatException {
      _showSnack(context.l10n.editorPleaseEnterValidAmount);
      return;
    }

    if (amount <= Decimal.zero) {
      _showSnack(context.l10n.editorAmountGreaterThanZero);
      return;
    }

    // #528: reject an amount whose integer subunits would exceed
    // Number.MAX_SAFE_INTEGER. Above it the persisted Dart int64 reads back as a
    // divergent JS number server-side, breaking balance-oracle parity. Checked
    // against effectiveCurrency (the actual write currency — widget.currency is
    // stale in add-mode after the picker).
    if (!MoneySerializer.fitsSafeSubunits(amount, effectiveCurrency)) {
      _showSnack(context.l10n.editorAmountTooLarge);
      return;
    }

    // #204: category is mandatory at CREATION — block the save until the user
    // picks one, so every new expense carries a real category (no null/"Other"
    // default). Removes the need for an "uncategorized" pre-settlement warning.
    // Edit mode is exempt: legacy null-category expenses stay editable without a
    // forced retroactive pick (the mandate is "at creation").
    if (!_isEdit &&
        (_selectedCategoryId == null || _selectedCategoryId!.isEmpty)) {
      setState(() => _categoryError = true);
      _showSnack(context.l10n.editorCategoryRequired);
      return;
    }

    // #250: an EXACT split is absolute amounts. If the amount was changed after
    // the split was set, the stored distribution no longer sums to the total
    // and BalanceCalculator._allocateExact would SILENTLY re-split equally,
    // destroying the user's stated amounts. (percent/shares are amount-
    // independent weights and re-derive correctly, so they're exempt.) Reject
    // here so the user can reopen the split and fix it, rather than persist a
    // stale split. Same 0.001 contract as the calculator's read-time check.
    if (_splitMode == SplitMode.exact && _splitDistribution != null) {
      final splitSum = _splitDistribution!.values.fold(
        Decimal.zero,
        (acc, v) => acc + v,
      );
      if ((splitSum - amount).abs() > _splitTolerance) {
        _showSnack(context.l10n.editorExactSplitOutOfSync);
        return;
      }
    }

    final currentParticipant = ref.read(
      currentEventParticipantProvider((
        groupId: widget.groupId,
        eventId: widget.eventId,
      )),
    );

    final payerId = _selectedPayerId ?? currentParticipant?.id;
    if (payerId == null) {
      _showSnack(context.l10n.editorCouldNotIdentifyParticipant);
      return;
    }

    HapticService.success();
    setState(() => _isSubmitting = true);

    try {
      final note = _noteController.text.trim();
      await widget.onSubmit(
        ExpenseEditorPayload(
          amount: amount,
          description: note.isNotEmpty ? note : null,
          scope: _scope,
          categoryId: _selectedCategoryId,
          payerParticipantId: payerId,
          customSplitParticipants: _scope == ExpenseScope.custom
              ? _customSplitParticipants.toList()
              : null,
          splitMode: _splitMode,
          splitDistribution: _splitMode == SplitMode.equally
              ? null
              : _splitDistribution,
          currency: effectiveCurrency,
          // #203 S2: itemized metadata only ever rides a non-equal split.
          // An equally split can never be itemized, so drop it there.
          splitExplanation: _splitMode == SplitMode.equally
              ? null
              : _splitExplanation,
        ),
      );
    } catch (e, st) {
      // #854: the raw cause goes to Sentry; the user sees a humanized phrase.
      unawaited(Sentry.captureException(e, stackTrace: st));
      if (mounted) {
        _showSnack(
          _isEdit
              ? context.l10n.editorFailedToUpdateExpense(
                  friendlyMessageFor(context, e),
                )
              : context.l10n.editorFailedToAddExpense(
                  friendlyMessageFor(context, e),
                ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _confirmDelete() async {
    final onDelete = widget.onDelete;
    if (onDelete == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.spacing.radiusCard),
        ),
        title: Row(
          children: [
            Icon(Iconsax.trash, color: context.colors.error),
            SizedBox(width: context.spacing.space12),
            Text(context.l10n.editorDeleteExpenseTitle),
          ],
        ),
        content: Text(context.l10n.editorDeleteExpenseBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              context.l10n.commonDelete,
              style: TextStyle(color: context.colors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      await onDelete();
    } catch (e, st) {
      // #854: the raw cause goes to Sentry; the user sees a humanized phrase.
      unawaited(Sentry.captureException(e, stackTrace: st));
      if (mounted) {
        _showSnack(
          context.l10n.editorDeleteExpenseFailed(
            friendlyMessageFor(context, e),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Shared dialog behind both [_confirmDiscard] (X / system back) and
  /// [_handleChangeDestination] (#900 — the editor's "change destination"
  /// tap): same copy, same stakes (the user is abandoning the current
  /// draft), different post-confirm action.
  Future<bool?> _showDiscardConfirmDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.spacing.radiusCard),
        ),
        title: Text(
          _isEdit
              ? context.l10n.editorDiscardEditTitle
              : context.l10n.editorDiscardAddTitle,
        ),
        content: Text(context.l10n.editorDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.editorDiscardKeepEditing),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              context.l10n.editorDiscardConfirm,
              style: TextStyle(color: context.colors.error),
            ),
          ),
        ],
      ),
    );
  }

  /// #818 Wave 3.2: shown when a dirty editor is about to be dismissed (X or
  /// system back — see [_handleClose] and the `PopScope` in [build]). Mirrors
  /// [_confirmDelete]'s house idiom but with no icon row (discarding a draft
  /// is lighter than deleting a persisted record) and the destructive action
  /// labeled "Discard" rather than "Delete".
  Future<void> _confirmDiscard() async {
    final confirmed = await _showDiscardConfirmDialog();

    if (confirmed == true && mounted) {
      // Imperative pop — bypasses `PopScope.canPop` by design (verified
      // against go_router 13.2.5's `delegate.dart`, which calls
      // `NavigatorState.pop` directly, never `maybePop`).
      context.pop();
    }
  }

  /// #900 (PR-5 §1): the trailing "change" tap on `WhereCard`, add mode
  /// only — wired at the [WhereCard] callsite as `_isEdit ? null :
  /// _handleChangeDestination`, so the null-check there IS the mode gate. A
  /// dirty form runs the SAME add-discard confirm as X/back (same stakes:
  /// abandoning this event's draft); on confirm (or when pristine) opens the
  /// target picker with `replaceCurrent: true` so the abandoned add editor is
  /// replaced, never stacked under Back.
  Future<void> _handleChangeDestination() async {
    HapticService.lightClick();
    if (_isDirty) {
      final confirmed = await _showDiscardConfirmDialog();
      if (confirmed != true || !mounted) return;
    }
    if (!mounted) return;
    await AddExpenseTargetSheet.show(context, replaceCurrent: true);
  }

  /// #818 Wave 3.2: single chokepoint for both dismissal paths (X tap; system
  /// back routes through `PopScope.onPopInvokedWithResult` instead, which
  /// calls [_confirmDiscard] directly since a blocked pop never reaches here).
  void _handleClose() {
    HapticService.lightClick();
    if (!_isDirty) {
      context.pop();
      return;
    }
    unawaited(_confirmDiscard());
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// #485: scope is now picked inline on the Split card. Switching it reseeds a
  /// fresh custom split to "just me" (#247, deselectable) and resets any stored
  /// distribution — the participant set changed, so a keyed distribution is
  /// stale and would confuse the balance calculator.
  void _handleScopeChange(ExpenseScope scope, String? currentParticipantId) {
    if (scope == _scope) return;
    HapticService.selection();
    setState(() {
      _customSplitParticipants = seedCustomSplitOnScopeChange(
        newScope: scope,
        current: _customSplitParticipants,
        currentParticipantId: currentParticipantId,
      );
      _scope = scope;
      _resetSplitToEqual();
    });
  }

  /// #485: toggling who's in a custom split lives inline now. Any change to the
  /// participant set invalidates a keyed distribution, so reset to equal.
  void _handleCustomSplitChange(Set<String> custom) {
    if (_setEquals(custom, _customSplitParticipants)) return;
    setState(() {
      _customSplitParticipants = custom;
      _resetSplitToEqual();
    });
  }

  void _resetSplitToEqual() {
    _splitMode = SplitMode.equally;
    _splitDistribution = null;
    _splitExplanation = null;
  }

  /// #485: the Split card's mode segment. Equal applies inline; the weighted
  /// modes open the existing weights sheet seeded with the requested mode.
  void _handlePickMode(Event event, SplitMode mode) {
    if (mode == SplitMode.equally) {
      if (_splitMode == SplitMode.equally) return;
      HapticService.selection();
      setState(_resetSplitToEqual);
      return;
    }
    _openSplitModeSheet(event, requestedMode: mode);
  }

  /// #280: dedicated "who paid" picker, reachable from the Paid-by section —
  /// not buried in the Split-between → Customise sheet. Changes only the single
  /// payerParticipantId field; the split set and its distribution are untouched.
  Future<void> _openPayerSheet(Event event) async {
    HapticService.lightClick();
    final currentId =
        _selectedPayerId ??
        ref
            .read(
              currentEventParticipantProvider((
                groupId: widget.groupId,
                eventId: widget.eventId,
              )),
            )
            ?.id;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) =>
          PayerPickerSheet(event: event, selectedPayerId: currentId),
    );
    if (selected != null && selected != _selectedPayerId) {
      HapticService.selection();
      setState(() => _selectedPayerId = selected);
    }
  }

  /// #382 PR-6: pick the currency this expense is denominated in (add mode
  /// only). Reuses the create-group [CurrencyPickerSheet]; a manual pick freezes
  /// the smart default ([_currencyManuallyPicked]) so a late event-history
  /// default can't clobber it.
  Future<void> _openCurrencySheet() async {
    HapticService.lightClick();
    final picked = await CurrencyPickerSheet.show(
      context,
      selected: effectiveCurrency,
    );
    if (picked == null || picked == _selectedCurrency || !mounted) return;
    HapticService.selection();
    setState(() {
      _selectedCurrency = picked;
      _currencyManuallyPicked = true;
    });
  }

  /// [requestedMode] (#485): when the user taps a specific weighted mode on the
  /// Split card's segment, open the sheet already on that tab; null reopens at
  /// the current mode. Switching to a different mode starts that tab fresh (a
  /// shares-weight distribution is not valid exact amounts).
  Future<void> _openSplitModeSheet(
    Event event, {
    SplitMode? requestedMode,
    bool forceItemized = false,
  }) async {
    HapticService.lightClick();
    final amount = Decimal.tryParse(_amount) ?? Decimal.zero;
    final ids = _splitParticipantIds(event);
    if (ids.length < 2) {
      _showSnack(context.l10n.editorPickAtLeastTwoPeople);
      return;
    }
    // split-clarity: the Itemized chip forces the itemized editor open. Itemized
    // persists as SplitMode.exact, so that's the base mode; carry the existing
    // items only when genuinely reopening an already-itemized expense.
    final alreadyItemized = _splitExplanation != null;
    final mode = forceItemized
        ? SplitMode.exact
        : (requestedMode ?? _splitMode);
    final sameMode = forceItemized ? alreadyItemized : (mode == _splitMode);
    // #289: distinguish two same-named members in the custom-split sheet.
    final displayNames = MemberNameResolver.disambiguateEventParticipants(
      event,
    );
    // #278: flag placeholder ("shadow") members who haven't joined yet. The
    // flag lives on GroupMember.isShadow; rows key by event-participant id,
    // which equals the member userId. Empty when the roster is unavailable.
    final members =
        ref.read(groupMembersProvider(event.groupId)).valueOrNull ?? const [];
    final shadowUserIds = {
      for (final m in members)
        if (m.isShadow) m.userId,
    };
    final participants = [
      for (final id in ids)
        SplitParticipant(
          id: id,
          name:
              displayNames[id] ??
              event.participantNames[id] ??
              context.l10n.editorMemberFallback,
          role: id == _selectedPayerId ? context.l10n.editorPaidRole : null,
          isShadow: shadowUserIds.contains(id),
        ),
    ];

    final result = await showCustomSplitSheet(
      context,
      title: _noteController.text.trim().isEmpty
          ? (_isEdit
                ? context.l10n.editorTitleEditExpense
                : context.l10n.editorTitleNewExpense)
          : _noteController.text.trim(),
      total: amount,
      currency: effectiveCurrency,
      participants: participants,
      initialMode: mode,
      initialDistribution: sameMode ? _splitDistribution : null,
      // #203 S2: reopen the itemized tab from the stored metadata (only when
      // staying in the same mode; a mode switch starts that tab fresh).
      // Items/adjustments only seed the ITEMIZED editor, which is now entered
      // exclusively via the Itemized chip (forceItemized). Tapping Exact/Shares/%
      // on an already-itemized expense must open that plain mode — seeded with the
      // current distribution (sameMode above), NOT reopen the itemized editor.
      initialItems: forceItemized ? _splitExplanation?.items : null,
      // #605: reopen the bill-level adjustments too.
      initialAdjustments: forceItemized ? _splitExplanation?.adjustments : null,
      initialItemized: forceItemized,
    );

    if (result == null || !mounted) return;
    setState(() {
      _splitMode = result.mode;
      _splitDistribution = result.distribution;
      // #203 S2: an itemized result carries its items; switching to any plain
      // mode returns items: null, which clears the metadata here (the UI-level
      // orphan guard — edit_expense_screen then FieldValue.deletes the field).
      _splitExplanation = result.items == null
          ? null
          : SplitExplanation(
              items: result.items!,
              // #605: carry the bill-level adjustments through, don't drop them.
              adjustments: result.adjustments,
            );
    });
  }

  List<String> _splitParticipantIds(Event event) {
    switch (_scope) {
      case ExpenseScope.global:
      case ExpenseScope.subGroup:
        return event.participantIds;
      case ExpenseScope.custom:
        // #247: the split is exactly the persisted custom set — no payer
        // auto-insertion (that made the preview lie vs the ledger). Mirror
        // BalanceCalculator: an empty set falls back to a global split over
        // all participants (expense_provider.dart custom-scope branch).
        return _customSplitParticipants.isEmpty
            ? event.participantIds
            : _customSplitParticipants.toList();
      case ExpenseScope.personal:
        return _selectedPayerId != null ? [_selectedPayerId!] : const [];
    }
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final v in a) {
      if (!b.contains(v)) return false;
    }
    return true;
  }

  /// uid → render-ready name for the event's participants (#289 disambiguation),
  /// memoized across the per-keystroke `build`s. Keyed on the event INSTANCE, not
  /// `Event ==` (which is id-only — #106): a same-id rename/member change arrives
  /// as a fresh Event instance, so identity refreshes the map; `==` would keep a
  /// stale name. INBOUND/display-only — write paths key by uid and strip the
  /// `(#…)` discriminator, never persist the returned string.
  Map<String, String> _disambiguatedNames(Event event) {
    if (!identical(event, _displayNamesKey)) {
      _displayNamesKey = event;
      debugEditorNameMapComputes++;
      _displayNames = MemberNameResolver.disambiguateEventParticipants(event);
    }
    return _displayNames;
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(tripCategoriesProvider(widget.eventId));
    final eventAsync = ref.watch(
      eventDetailProvider((groupId: widget.groupId, eventId: widget.eventId)),
    );
    final event = eventAsync.valueOrNull;
    final currentParticipant = ref.watch(
      currentEventParticipantProvider((
        groupId: widget.groupId,
        eventId: widget.eventId,
      )),
    );

    return PopScope(
      // #818 Wave 3.2: a pristine screen keeps canPop true so Android
      // predictive-back preview stays alive; a dirty screen blocks the pop
      // and routes system-back through the same discard dialog as the X.
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_confirmDiscard());
      },
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBackground,
        body: SafeArea(
          child: Column(
            children: [
              ExpenseTopBar(
                title: _isEdit
                    ? context.l10n.editorTitleEditExpense
                    : context.l10n.editorTitleAddExpense,
                actionLabel: _isEdit
                    ? context.l10n.editorActionSave
                    : context.l10n.editorActionAdd,
                isLoading: _isSubmitting,
                onClose: _handleClose,
                onAction: _submit,
              ),
              const OfflineBanner(),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: context.spacing.space24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AmountHero(
                        controller: _amountController,
                        focusNode: _amountFocusNode,
                        amount: _amount,
                        currency: effectiveCurrency,
                        onChanged: (value) =>
                            setState(() => _amount = _sanitizeAmount(value)),
                        onTap: _queueSelectDefaultZero,
                      ),
                      // #382 PR-6: per-expense currency picker (add mode only).
                      // Edit keeps the stored currency immutable (changing it would
                      // strand any settlement recorded against the old bucket).
                      if (!_isEdit)
                        CurrencyRow(
                          key: LedgerKeys.expenseCurrencyField,
                          currency: effectiveCurrency,
                          onTap: _openCurrencySheet,
                        ),
                      // #382 PR-6: soft fat-finger warning — non-blocking, reactive.
                      // Shown only when the picked currency diverges from the
                      // event's dominant (most-frequent) one; picking the dominant
                      // makes it vanish. Never in edit mode (currency is immutable).
                      if (!_isEdit &&
                          widget.dominantCurrency != null &&
                          effectiveCurrency != widget.dominantCurrency)
                        CurrencyMismatchNotice(
                          key: LedgerKeys.expenseCurrencyWarning,
                          selected: effectiveCurrency,
                          dominant: widget.dominantCurrency!,
                        ),
                      DescriptionField(controller: _noteController),
                      // #248 PR5: provenance byline — who ADDED / last EDITED this
                      // expense, distinct from who PAID (the "Paid by" card). Edit
                      // mode only, and only once the event has resolved (names
                      // come from its participantNames map).
                      if (_isEdit && event != null && widget.initial != null)
                        ExpenseProvenanceByline(
                          displayNames: _disambiguatedNames(event),
                          event: event,
                          expense: widget.initial!,
                        ),
                      EditorSection(
                        title: context.l10n.editorCategory,
                        // #807: category is mandatory at creation (#787) — mark
                        // it required up front instead of only on blocked submit.
                        showRequiredMarker: !_isEdit,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_categoryError)
                              Padding(
                                padding: EdgeInsetsDirectional.only(
                                  start: context.spacing.space24,
                                  bottom: context.spacing.space8,
                                ),
                                child: Text(
                                  context.l10n.editorCategoryRequired,
                                  style: AppTypography.sans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: context.colors.error,
                                  ),
                                ),
                              ),
                            CategoryStrip(
                              categoriesAsync: categoriesAsync,
                              eventType: event?.type,
                              selectedCategoryId: _selectedCategoryId,
                              onCategorySelected: (id) {
                                HapticService.selection();
                                setState(() {
                                  _selectedCategoryId = id;
                                  _categoryError = false;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      if (event != null) ...[
                        // #485: one Split card — single payer control, plain-
                        // language scope, inline mode segment, real per-person
                        // figures (#242). Replaces the former Paid-by / Split-
                        // between / How sections and the duplicate payer picker.
                        EditorSection(
                          title: context.l10n.editorSplit,
                          child: SplitCard(
                            event: event,
                            displayNames: _disambiguatedNames(event),
                            amount: Decimal.tryParse(_amount) ?? Decimal.zero,
                            currency: effectiveCurrency,
                            scope: _scope,
                            payerId: _selectedPayerId ?? currentParticipant?.id,
                            selfId: currentParticipant?.id,
                            customSplitParticipants: _customSplitParticipants,
                            splitMode: _splitMode,
                            splitDistribution: _splitDistribution,
                            splitExplanation: _splitExplanation,
                            onChangePayer: () => _openPayerSheet(event),
                            onScopeChanged: (scope) => _handleScopeChange(
                              scope,
                              currentParticipant?.id,
                            ),
                            onCustomSplitChanged: _handleCustomSplitChange,
                            onPickMode: (mode) => _handlePickMode(event, mode),
                            // split-clarity: Itemized opens its editor directly,
                            // instead of the old "tap Exact → find the 5th chip".
                            onPickItemized: () =>
                                _openSplitModeSheet(event, forceItemized: true),
                          ),
                        ),
                        EditorSection(
                          title: context.l10n.editorWhere,
                          child: WhereCard(
                            event: event,
                            // Add mode only — the null-check on the other
                            // side IS the mode gate (#900). An existing
                            // expense is pinned to its event.
                            onChangeDestination: _isEdit
                                ? null
                                : _handleChangeDestination,
                          ),
                        ),
                      ] else
                        Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: context.spacing.space24,
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      if (_isEdit && widget.onDelete != null)
                        DeleteCard(
                          enabled: !_isSubmitting,
                          onDelete: _confirmDelete,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _sanitizeAmount(String value) {
    final maxDecimals =
        AppFormatters.currencyConfig[effectiveCurrency]?.decimals ?? 3;
    final normalized = normalizeLocalizedDecimalInput(
      value,
      decimalDigits: maxDecimals,
    );
    return normalized.isEmpty ? '0' : normalized;
  }
}

/// #627 perf seam: counts how often the editor recomputes the SHARED
/// disambiguation name map (`_disambiguatedNames`), shared with the paid-by
/// and split consumers. Tests assert a pure amount keystroke does NOT recompute
/// it. Reset in test `setUp`; production never reads it. (The owed-allocation
/// counter moved to `split_card.dart` with the per-person figures.)
@visibleForTesting
int debugEditorNameMapComputes = 0;
