import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/services/money_serializer.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/currency_display_name.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/localized_decimal_input.dart';
import '../../../core/utils/localized_name_validators.dart';
import '../../../shared/widgets/directional_icon.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../../events/models/event_model.dart';
import '../../events/providers/event_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../../groups/services/member_name_resolver.dart';
import '../../groups/widgets/currency_picker_sheet.dart';
import '../../trip/providers/trip_provider.dart';
import '../keys/ledger_keys.dart';
import '../models/expense_category_model.dart';
import '../models/expense_model.dart';
import '../models/split_explanation.dart';
import '../providers/category_provider.dart';
import '../utils/expense_provenance.dart';
import '../utils/ledger_categories.dart';
import '../utils/localized_category_name.dart';
import 'custom_split_sheet.dart';
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

  /// #627 follow-up: the disambiguation name map is event-derived and shared by
  /// every in-build consumer (`_PaidByCard`, `_ExpenseProvenanceByline`,
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
  }

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
    if (!_isEdit && (_selectedCategoryId == null || _selectedCategoryId!.isEmpty)) {
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
    } catch (e) {
      if (mounted) {
        _showSnack(
          _isEdit
              ? context.l10n.editorFailedToUpdateExpense(e.toString())
              : context.l10n.editorFailedToAddExpense(e.toString()),
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
    } catch (e) {
      if (mounted) {
        _showSnack(context.l10n.editorDeleteExpenseFailed(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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
          _PayerPickerSheet(event: event, selectedPayerId: currentId),
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
  }) async {
    HapticService.lightClick();
    final amount = Decimal.tryParse(_amount) ?? Decimal.zero;
    final ids = _splitParticipantIds(event);
    if (ids.length < 2) {
      _showSnack(context.l10n.editorPickAtLeastTwoPeople);
      return;
    }
    final mode = requestedMode ?? _splitMode;
    final sameMode = mode == _splitMode;
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
      initialItems: sameMode ? _splitExplanation?.items : null,
      // #605: reopen the bill-level adjustments too.
      initialAdjustments: sameMode ? _splitExplanation?.adjustments : null,
      initialItemized: sameMode ? _splitExplanation != null : false,
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

    return Scaffold(
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            _ExpenseTopBar(
              title: _isEdit
                  ? context.l10n.editorTitleEditExpense
                  : context.l10n.editorTitleAddExpense,
              actionLabel: _isEdit
                  ? context.l10n.editorActionSave
                  : context.l10n.editorActionAdd,
              isLoading: _isSubmitting,
              onClose: () {
                HapticService.lightClick();
                context.pop();
              },
              onAction: _submit,
            ),
            const OfflineBanner(),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(bottom: context.spacing.space24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AmountHero(
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
                      _CurrencyRow(
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
                      _CurrencyMismatchNotice(
                        key: LedgerKeys.expenseCurrencyWarning,
                        selected: effectiveCurrency,
                        dominant: widget.dominantCurrency!,
                      ),
                    _DescriptionField(controller: _noteController),
                    // #248 PR5: provenance byline — who ADDED / last EDITED this
                    // expense, distinct from who PAID (the "Paid by" card). Edit
                    // mode only, and only once the event has resolved (names
                    // come from its participantNames map).
                    if (_isEdit && event != null && widget.initial != null)
                      _ExpenseProvenanceByline(
                        displayNames: _disambiguatedNames(event),
                        event: event,
                        expense: widget.initial!,
                      ),
                    _Section(
                      title: context.l10n.editorCategory,
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
                          _CategoryStrip(
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
                      _Section(
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
                          onScopeChanged: (scope) =>
                              _handleScopeChange(scope, currentParticipant?.id),
                          onCustomSplitChanged: _handleCustomSplitChange,
                          onPickMode: (mode) => _handlePickMode(event, mode),
                        ),
                      ),
                      _Section(
                        title: context.l10n.editorWhere,
                        child: _WhereCard(event: event),
                      ),
                    ] else
                      Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: context.spacing.space24,
                        ),
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                    if (_isEdit && widget.onDelete != null)
                      _DeleteCard(
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

class _ExpenseTopBar extends StatelessWidget {
  const _ExpenseTopBar({
    required this.title,
    required this.actionLabel,
    required this.isLoading,
    required this.onClose,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final bool isLoading;
  final VoidCallback onClose;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 20, 8),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: IconButton(
                tooltip: context.l10n.commonClose,
                icon: const Icon(Iconsax.close_circle, size: 20),
                color: context.colors.textPrimary,
                onPressed: onClose,
              ),
            ),
            Text(
              title,
              style: AppTypography.sans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                onPressed: isLoading ? null : onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  foregroundColor: context.colors.textOnPrimary,
                  minimumSize: const Size(64, 40),
                  padding: EdgeInsetsDirectional.fromSTEB(
                    context.spacing.space16,
                    9,
                    context.spacing.space16,
                    11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      context.spacing.radiusSmall,
                    ),
                  ),
                  textStyle: AppTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.22,
                  ).copyWith(leadingDistribution: TextLeadingDistribution.even),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountHero extends StatelessWidget {
  const _AmountHero({
    required this.controller,
    required this.focusNode,
    required this.amount,
    required this.currency,
    required this.onChanged,
    required this.onTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String amount;
  final String currency;
  final ValueChanged<String> onChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final parts = amount.split('.');
    final whole = parts.first.isEmpty ? '0' : parts.first;
    final rawFraction = parts.length > 1 ? parts.last : '';
    final decimals = AppFormatters.currencyConfig[currency]?.decimals ?? 3;
    // Pad the DISPLAYED fraction to the currency's precision so the live field
    // matches the 3dp shown in the saved expense and summaries (#156). This is
    // display-only: the parsed/persisted Decimal comes from the (transparent)
    // controller, never this string, so padding here cannot change the written
    // value. The untouched default '0' stays a clean unpadded 'OMR 0'.
    final fraction = (amount != '0' && decimals > 0)
        ? '.${rawFraction.padRight(decimals, '0')}'
        : (rawFraction.isEmpty ? '' : '.$rawFraction');
    final colors = context.colors;

    // The label color is deliberately darker than textSecondary — at fontSize
    // 10 with extra letter spacing it can otherwise blend into the cream
    // background on iOS.
    final labelColor = colors.textPrimary.withValues(alpha: 0.55);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Forced LTR like the amount Row below — otherwise the composite
              // 'المبلغ · OMR' inherits the ambient RTL and scrambles (#150).
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  context.l10n.editorAmountLabel(currency),
                  style: AppTypography.mono(
                    fontSize: 10,
                    letterSpacing: 1.6,
                    color: labelColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(height: context.spacing.space12),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(bottom: context.spacing.space12),
                      child: Text(
                        currency,
                        style: AppTypography.mono(
                          fontSize: 20,
                          color: colors.textSecondary,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      whole,
                      style: AppTypography.mono(
                        fontSize: 64,
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w500,
                        height: 1.05,
                      ),
                    ),
                    if (fraction.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: context.spacing.space8,
                        ),
                        child: Text(
                          fraction,
                          style: AppTypography.mono(
                            fontSize: 28,
                            color: colors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: 120,
                height: 2,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
          Positioned.fill(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onTap: onTap,
              onChanged: onChanged,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              // The transparent overlay field only types digits; disabling
              // interactive selection stops iOS selection handles from sticking
              // over the amount label (#150). Programmatic select-default-zero
              // still works (it sets controller.selection directly).
              enableInteractiveSelection: false,
              textDirection: TextDirection.ltr,
              inputFormatters: [
                LocalizedDecimalTextInputFormatter(
                  decimalDigits:
                      AppFormatters.currencyConfig[currency]?.decimals ?? 3,
                ),
              ],
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.transparent),
              cursorColor: Colors.transparent,
              decoration: const InputDecoration(
                filled: false,
                fillColor: Colors.transparent,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DescriptionField extends StatefulWidget {
  const _DescriptionField({required this.controller});

  final TextEditingController controller;

  @override
  State<_DescriptionField> createState() => _DescriptionFieldState();
}

class _DescriptionFieldState extends State<_DescriptionField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  // Recompute the inline error as the user types so an over-length / control-
  // char note shows a message instead of an opaque permission-denied (#220).
  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final errorText = validateFreeTextLocalized(
      context,
      widget.controller.text,
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space24),
      child: TextField(
        controller: widget.controller,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: context.l10n.editorDescriptionLabel,
          hintText: context.l10n.editorDescriptionHint,
          errorText: errorText,
          filled: true,
          fillColor: context.colors.scaffoldBackground,
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: context.colors.rule2),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: context.colors.primary, width: 1.5),
          ),
          errorBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: context.colors.error),
          ),
          focusedErrorBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: context.colors.error, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// #382 PR-6: tappable row showing the picked currency (code + display name)
/// with a trailing chevron. Opens [CurrencyPickerSheet]. Add mode only.
class _CurrencyRow extends StatelessWidget {
  const _CurrencyRow({super.key, required this.currency, required this.onTap});

  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        context.spacing.space24,
        context.spacing.space8,
        context.spacing.space24,
        0,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: _CardShell(
          child: _InfoRow(
            leading: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.selectionFill,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Iconsax.dollar_circle,
                size: 18,
                color: colors.primary,
              ),
            ),
            title: currencyDisplayName(currency, context.l10n),
            subtitle: currency,
            trailing: DirectionalIcon(
              Iconsax.arrow_right_3,
              size: 18,
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// #382 PR-6: inline, non-blocking soft warning shown in the add-expense form
/// when the picked currency diverges from the event's dominant (most-frequent)
/// one — a fat-finger guard. Amber soft-notice idiom (tint + icon + text); it
/// never blocks submit and vanishes reactively when the dominant is picked.
class _CurrencyMismatchNotice extends StatelessWidget {
  const _CurrencyMismatchNotice({
    super.key,
    required this.selected,
    required this.dominant,
  });

  final String selected;
  final String dominant;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        context.spacing.space24,
        context.spacing.space8,
        context.spacing.space24,
        0,
      ),
      child: Container(
        padding: EdgeInsets.all(context.spacing.space12),
        decoration: BoxDecoration(
          color: colors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.warning.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Iconsax.warning_2, size: 18, color: colors.warning),
            SizedBox(width: context.spacing.space8),
            Expanded(
              child: Text(
                context.l10n.editorCurrencyMismatch(selected, dominant),
                style: AppTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// #248 PR5: compact "Added by … · edited by …" byline under the description.
/// Reads the expense's createdBy / lastEditedBy uids and resolves them through
/// the same disambiguated participantNames chain the payer uses, so creator and
/// payer are surfaced side by side without conflating them. Renders nothing for
/// legacy expenses with no creator.
class _ExpenseProvenanceByline extends StatelessWidget {
  const _ExpenseProvenanceByline({
    required this.displayNames,
    required this.event,
    required this.expense,
  });

  /// #289 disambiguation map, shared from the parent (#627 follow-up).
  final Map<String, String> displayNames;
  final Event event;
  final Expense expense;

  @override
  Widget build(BuildContext context) {
    String resolve(String uid) =>
        displayNames[uid] ??
        event.participantNames[uid] ??
        context.l10n.activitySomeone;

    final provenance = resolveExpenseProvenance(
      createdBy: expense.createdBy,
      lastEditedBy: expense.lastEditedBy,
      resolveName: resolve,
    );
    if (provenance == null) return const SizedBox.shrink();

    final text = provenance.editorName == null
        ? context.l10n.editorProvenanceAdded(provenance.creatorName)
        : context.l10n.editorProvenanceAddedEdited(
            provenance.creatorName,
            provenance.editorName!,
          );

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        context.spacing.space24,
        context.spacing.space8,
        context.spacing.space24,
        0,
      ),
      child: Text(
        text,
        style: AppTypography.sans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: context.spacing.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.spacing.space24),
            child: Text(
              title,
              style: AppTypography.sans(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({
    required this.categoriesAsync,
    required this.selectedCategoryId,
    required this.onCategorySelected,
    this.eventType,
  });

  final AsyncValue<List<ExpenseCategory>> categoriesAsync;
  final String? selectedCategoryId;
  final ValueChanged<String> onCategorySelected;

  /// #689: when set, reorders the picker so the event type's likely categories
  /// lead (camping → groceries/fuel first). Null (event still loading) → the
  /// neutral catalog order.
  final EventType? eventType;

  @override
  Widget build(BuildContext context) {
    return categoriesAsync.when(
      loading: () => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space24,
          vertical: context.spacing.space12,
        ),
        child: const LinearProgressIndicator(),
      ),
      error: (_, _) => Padding(
        padding: EdgeInsets.symmetric(horizontal: context.spacing.space24),
        child: Text(
          context.l10n.editorCouldNotLoadCategories,
          style: TextStyle(color: context.colors.errorText),
        ),
      ),
      data: (categories) {
        final order = categoryOrderForType(eventType ?? EventType.custom);
        final sorted = [...categories]
          ..sort((a, b) => order.indexOf(a.id).compareTo(order.indexOf(b.id)));
        return SizedBox(
          height: 42,
          child: ListView.separated(
            padding: EdgeInsets.symmetric(
              horizontal: context.spacing.space24,
            ),
            scrollDirection: Axis.horizontal,
            itemCount: sorted.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final category = sorted[index];
              return _CategoryChip(
                category: category,
                selected: selectedCategoryId == category.id,
                onTap: () => onCategorySelected(category.id),
              );
            },
          ),
        );
      },
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final ExpenseCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = categoryColorForId(context.colors, category.id);
    final displayName = localizedCategoryName(
      id: category.id,
      fallbackName: category.name,
      l10n: context.l10n,
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
        decoration: BoxDecoration(
          color: selected
              ? context.colors.textPrimary
              : context.colors.cardSurface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? context.colors.textPrimary : context.colors.rule2,
          ),
          boxShadow: selected ? context.shadows.flat : context.shadows.raised,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.18)
                    : context.colors.cardSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                categoryIconForId(category.id),
                size: 11,
                color: selected ? Colors.white : color,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              displayName,
              style: AppTypography.sans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected
                    ? context.colors.scaffoldBackground
                    : context.colors.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// #627 perf seam: counts how often the editor recomputes the SHARED
/// disambiguation name map (`_disambiguatedNames`), shared with the paid-by
/// and split consumers. Tests assert a pure amount keystroke does NOT recompute
/// it. Reset in test `setUp`; production never reads it. (The owed-allocation
/// counter moved to `split_card.dart` with the per-person figures.)
@visibleForTesting
int debugEditorNameMapComputes = 0;

class _WhereCard extends StatelessWidget {
  const _WhereCard({required this.event});

  final Event event;

  @override
  Widget build(BuildContext context) {
    final date = event.startDate ?? event.createdAt;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space24),
      child: _CardShell(
        child: Column(
          children: [
            _InfoRow(
              title: context.l10n.editorEvent,
              trailingText: event.name,
              dense: true,
            ),
            _InfoRow(
              title: context.l10n.editorDate,
              trailingText: AppFormatters.formatShortMonthDay(
                date,
                Localizations.localeOf(context).toLanguageTag(),
              ),
              dense: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteCard extends StatelessWidget {
  const _DeleteCard({required this.enabled, required this.onDelete});

  final bool enabled;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Container(
        padding: EdgeInsets.all(context.spacing.space16),
        decoration: BoxDecoration(
          color: colors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
          border: Border.all(color: colors.error.withValues(alpha: 0.16)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.editorDeleteThisExpense,
                    style: AppTypography.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.editorDeleteThisExpenseBody,
                    style: AppTypography.sans(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: context.spacing.space12),
            FilledButton.icon(
              onPressed: enabled ? onDelete : null,
              icon: const Icon(Iconsax.trash, size: 14),
              label: Text(context.l10n.commonDelete),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsetsDirectional.fromSTEB(14, 9, 14, 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    context.spacing.radiusSmall,
                  ),
                ),
                textStyle: AppTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.22,
                ).copyWith(leadingDistribution: TextLeadingDistribution.even),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardSurface,
        borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
        boxShadow: context.shadows.raised,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.trailingText,
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final String? trailingText;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 12 : 14),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            SizedBox(width: context.spacing.space12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: AppTypography.sans(
                      fontSize: 12,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else if (trailingText != null)
            Flexible(
              child: Text(
                trailingText!,
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.sans(
                  fontSize: 13,
                  color: context.colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// #280: single-choice "who paid" picker. Tap a participant to select and
/// close, returning the chosen id via [Navigator.pop]. Render-only names
/// (disambiguated, #289); the caller writes the id.
class _PayerPickerSheet extends StatelessWidget {
  const _PayerPickerSheet({required this.event, required this.selectedPayerId});

  final Event event;
  final String? selectedPayerId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final displayNames = MemberNameResolver.disambiguateEventParticipants(
      event,
    );
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colors.scaffoldBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                context.spacing.space20,
                context.spacing.space4,
                context.spacing.space20,
                context.spacing.space12,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  context.l10n.editorPaidBy,
                  style: AppTypography.sans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  for (final id in event.participantIds)
                    _PayerOption(
                      name:
                          displayNames[id] ??
                          event.participantNames[id] ??
                          context.l10n.editorUnknownParticipant,
                      selected: id == selectedPayerId,
                      onTap: () => Navigator.of(context).pop(id),
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

class _PayerOption extends StatelessWidget {
  const _PayerOption({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsetsDirectional.symmetric(
        horizontal: context.spacing.space12,
      ),
      leading: RAvatar(name: name, size: 36),
      title: Text(
        name,
        style: AppTypography.sans(
          fontSize: 15,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: colors.textPrimary,
        ),
      ),
      trailing: selected
          ? Icon(Iconsax.tick_circle, color: colors.primary, size: 20)
          : null,
    );
  }
}
