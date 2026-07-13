part of 'custom_split_sheet.dart';

// ───────────────────────────────────────── itemized split widgets (#203 S2)
//
// Presentational widgets + the per-row draft model for the itemized split tab.
// A `part of` the custom_split_sheet library so these stay private and share
// SplitParticipant / the sheet's imports without a circular dependency. The
// sheet state (the `_itemized` flag, `_itemizedCanApply`, `_buildItemizedResult`)
// lives in custom_split_sheet.dart and drives these via props; the `_ModeSegmented`
// tab-bar that toggles itemized lives in the custom_split_sheet_mode_selector.dart part.

/// Mutable editor state for one itemized line item. Owns its text controllers;
/// the sheet state disposes them. [quantity]/[allocation] are not editable in
/// v1, so a draft built from a reopened item preserves them.
class _ItemDraft {
  _ItemDraft({
    required this.label,
    required this.amount,
    required Set<String> assignees,
    this.quantity = 1,
    this.allocation = 'equal',
  }) : assignees = {...assignees};

  factory _ItemDraft.empty() => _ItemDraft(
        label: TextEditingController(),
        amount: TextEditingController(),
        assignees: const {},
      );

  factory _ItemDraft.fromItem(SplitItem item, String currency) {
    final amount = MoneySerializer.isSupported(currency)
        ? MoneySerializer.fromSubunits(item.amountFils, currency)
        : Decimal.fromInt(item.amountFils);
    return _ItemDraft(
      label: TextEditingController(text: item.label),
      amount: TextEditingController(text: _trimDecimal(amount)),
      assignees: item.participantIds.toSet(),
      quantity: item.quantity,
      allocation: item.allocation,
    );
  }

  final TextEditingController label;
  final TextEditingController amount;
  final Set<String> assignees;
  final int quantity;
  final String allocation;

  /// Build a [SplitItem] from this draft. Caller MUST have checked the amount
  /// parses > 0 and there is ≥1 assignee (the allocator throws otherwise).
  SplitItem toItem(String currency) => SplitItem(
        label: label.text.trim(),
        amountFils: MoneySerializer.isSupported(currency)
            ? MoneySerializer.toSubunits(Decimal.parse(amount.text), currency)
            : Decimal.parse(amount.text).toBigInt().toInt(),
        quantity: quantity,
        participantIds: assignees.toList(),
        allocation: allocation,
      );

  void dispose() {
    label.dispose();
    amount.dispose();
  }

  static String _trimDecimal(Decimal v) {
    final s = v.toString();
    if (!s.contains('.')) return s;
    var trimmed = s.replaceFirst(RegExp(r'0+$'), '');
    if (trimmed.endsWith('.')) trimmed = trimmed.substring(0, trimmed.length - 1);
    return trimmed;
  }
}

/// Mutable editor state for one bill-level adjustment (#605). Owns its amount
/// controller (disposed by the sheet state). [type] ∈ [kAdjustmentTypes];
/// [allocation] is 'equal' or 'proportional' for an additive; a discount is
/// 'proportional' (default) or 'assigned' — an assigned discount is borne by
/// the [participantIds] subset. [toAdjustment] is the OUTBOUND normalization
/// point (empty/invalid assigned selection degrades to 'proportional').
class _AdjustmentDraft {
  _AdjustmentDraft({
    required this.amount,
    this.type = 'service',
    this.allocation = 'equal',
    List<String> participantIds = const [],
  }) : participantIds = [...participantIds];

  factory _AdjustmentDraft.empty() =>
      _AdjustmentDraft(amount: TextEditingController());

  factory _AdjustmentDraft.fromAdjustment(SplitAdjustment a, String currency) {
    final amount = MoneySerializer.isSupported(currency)
        ? MoneySerializer.fromSubunits(a.amountFils, currency)
        : Decimal.fromInt(a.amountFils);
    return _AdjustmentDraft(
      amount: TextEditingController(text: _ItemDraft._trimDecimal(amount)),
      type: a.type,
      allocation: a.allocation,
      // Reopen touch-point (#605): an assigned discount reconstructs its subset.
      participantIds: a.participantIds ?? const [],
    );
  }

  final TextEditingController amount;
  String type;
  String allocation;

  /// Who bears an 'assigned' discount (mutable; edited by the member picker).
  final List<String> participantIds;

  /// Build a [SplitAdjustment]. Caller MUST have checked the amount parses > 0.
  /// Mirrors [_ItemDraft.toItem]'s subunit conversion byte-for-byte (incl. the
  /// unsupported-currency truncation) so preview == persisted. This is the
  /// single OUTBOUND normalization point:
  ///  - a non-discount emits no `participantIds` (always additive);
  ///  - a discount is 'proportional' (default) OR 'assigned' — but an
  ///    'assigned' selection with NO chosen members degrades to 'proportional'
  ///    HERE so an empty-subset draft can never reach the allocator (which
  ///    throws on an empty assigned subset).
  SplitAdjustment toAdjustment(String currency) {
    final amountFils = MoneySerializer.isSupported(currency)
        ? MoneySerializer.toSubunits(Decimal.parse(amount.text), currency)
        : Decimal.parse(amount.text).toBigInt().toInt();
    if (type != 'discount') {
      return SplitAdjustment(
        type: type,
        amountFils: amountFils,
        allocation: allocation,
      );
    }
    final assigned = allocation == 'assigned' && participantIds.isNotEmpty;
    return SplitAdjustment(
      type: 'discount',
      amountFils: amountFils,
      allocation: assigned ? 'assigned' : 'proportional',
      participantIds: assigned ? [...participantIds] : null,
    );
  }

  void dispose() => amount.dispose();
}

/// Localized label for an adjustment [type] (one of [kAdjustmentTypes]).
String _adjustmentTypeLabel(BuildContext context, String type) {
  final l10n = context.l10n;
  switch (type) {
    case 'tax':
      return l10n.adjustmentTypeTax;
    case 'tip':
      return l10n.adjustmentTypeTip;
    case 'discount':
      return l10n.adjustmentTypeDiscount;
    case 'service':
    default:
      return l10n.adjustmentTypeService;
  }
}

class _ItemizedBody extends StatelessWidget {
  const _ItemizedBody({
    super.key,
    required this.drafts,
    required this.adjDrafts,
    required this.participants,
    required this.currency,
    required this.preview,
    required this.assignedDiscountError,
    required this.draftValid,
    required this.onChanged,
    required this.onAddItem,
    required this.onRemoveItem,
    required this.onAddAdjustment,
    required this.onEditAdjustment,
    required this.onRemoveAdjustment,
  });

  final List<_ItemDraft> drafts;
  final List<_AdjustmentDraft> adjDrafts;
  final List<SplitParticipant> participants;
  final String currency;

  /// Live per-person owed from the currently-valid drafts (computed by the
  /// sheet state; excludes rows missing an amount/assignee). On an assigned-
  /// discount overshoot this is the LAST VALID fold (never zeroed).
  final Map<String, Decimal> preview;

  /// True when an assigned discount overshoots its subset (#605) — the sheet
  /// shows an inline error and Apply is disabled; the [preview] still renders
  /// the last valid distribution so no misleading zeros flash mid-edit.
  final bool assignedDiscountError;
  final bool Function(_ItemDraft draft) draftValid;
  final VoidCallback onChanged;
  final VoidCallback onAddItem;
  final ValueChanged<_ItemDraft> onRemoveItem;
  final VoidCallback onAddAdjustment;
  final ValueChanged<_AdjustmentDraft> onEditAdjustment;
  final ValueChanged<_AdjustmentDraft> onRemoveAdjustment;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ItemizedSectionHeader(
          label: l10n.itemizedItemsHeader,
          action: l10n.itemizedAddItem,
          actionKey: const Key('itemized_add_item'),
          onAction: onAddItem,
        ),
        SizedBox(height: spacing.space8),
        Container(
          decoration: BoxDecoration(
            color: colors.cardSurface,
            borderRadius: BorderRadius.circular(spacing.radiusLarge),
            boxShadow: context.shadows.raised,
          ),
          padding: EdgeInsets.symmetric(horizontal: spacing.space16),
          child: Column(
            children: [
              for (var i = 0; i < drafts.length; i++)
                _ItemRow(
                  index: i,
                  draft: drafts[i],
                  participants: participants,
                  currency: currency,
                  showDivider: i < drafts.length - 1,
                  canRemove: drafts.length > 1,
                  needsAssignee: !draftValid(drafts[i]) &&
                      drafts[i].assignees.isEmpty,
                  onChanged: onChanged,
                  onRemove: () => onRemoveItem(drafts[i]),
                ),
            ],
          ),
        ),
        SizedBox(height: spacing.space16),
        _AdjustmentsSection(
          adjDrafts: adjDrafts,
          participants: participants,
          currency: currency,
          onAdd: onAddAdjustment,
          onEdit: onEditAdjustment,
          onRemove: onRemoveAdjustment,
        ),
        if (assignedDiscountError) ...[
          SizedBox(height: spacing.space12),
          Row(
            children: [
              Icon(Icons.error_outline, size: 16, color: colors.error),
              SizedBox(width: spacing.space8),
              Expanded(
                child: Text(
                  key: const Key('assigned_discount_error'),
                  l10n.adjustmentDiscountExceedsSubset,
                  style: AppTypography.sans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.error,
                  ),
                ),
              ),
            ],
          ),
        ],
        SizedBox(height: spacing.space16),
        _ItemizedSectionHeader(label: l10n.itemizedEachOwes),
        SizedBox(height: spacing.space8),
        Container(
          decoration: BoxDecoration(
            color: colors.cardSurface,
            borderRadius: BorderRadius.circular(spacing.radiusLarge),
            boxShadow: context.shadows.raised,
          ),
          padding: EdgeInsets.symmetric(horizontal: spacing.space16),
          child: Column(
            children: [
              for (var i = 0; i < participants.length; i++)
                _OwesRow(
                  name: participants[i].name,
                  colorKey: participants[i].id,
                  role: participants[i].role,
                  owed: preview[participants[i].id] ?? Decimal.zero,
                  currency: currency,
                  showDivider: i < participants.length - 1,
                ),
            ],
          ),
        ),
        SizedBox(height: spacing.space12),
      ],
    );
  }
}

class _ItemizedSectionHeader extends StatelessWidget {
  const _ItemizedSectionHeader({
    required this.label,
    this.action,
    this.actionKey,
    this.onAction,
  });

  final String label;
  final String? action;
  final Key? actionKey;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypography.caption(
              context,
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
              color: colors.textSecondary,
            ),
          ),
        ),
        if (action != null)
          GestureDetector(
            key: actionKey,
            behavior: HitTestBehavior.opaque,
            onTap: onAction,
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: context.spacing.space4,
                horizontal: context.spacing.space4,
              ),
              child: Text(
                action!,
                style: AppTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryDark,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.index,
    required this.draft,
    required this.participants,
    required this.currency,
    required this.showDivider,
    required this.canRemove,
    required this.needsAssignee,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _ItemDraft draft;
  final List<SplitParticipant> participants;
  final String currency;
  final bool showDivider;
  final bool canRemove;
  final bool needsAssignee;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final l10n = context.l10n;
    final decimals = AppFormatters.currencyConfig[currency]?.decimals ?? 3;

    return Container(
      padding: EdgeInsets.symmetric(vertical: spacing.space12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: showDivider ? colors.rule : Colors.transparent,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  key: Key('itemized_label_$index'),
                  controller: draft.label,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l10n.itemizedItemLabelHint,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
              SizedBox(width: spacing.space12),
              SizedBox(
                width: 110,
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    key: Key('itemized_amount_$index'),
                    controller: draft.amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.right,
                    inputFormatters: [
                      LocalizedDecimalTextInputFormatter(
                        decimalDigits: decimals,
                      ),
                    ],
                    style: AppTypography.mono(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      suffixText: currency,
                      suffixStyle: AppTypography.mono(
                        fontSize: 12,
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: spacing.space8,
                        vertical: spacing.space8,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: colors.rule2),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            BorderSide(color: colors.primary, width: 1.2),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: colors.rule2),
                      ),
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ),
              if (canRemove)
                IconButton(
                  key: Key('itemized_remove_$index'),
                  tooltip: l10n.itemizedRemoveItem,
                  icon: const Icon(Icons.close, size: 16),
                  color: colors.textSecondary,
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    HapticService.selection();
                    onRemove();
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          _AssigneeSummary(
            index: index,
            draft: draft,
            participants: participants,
            needsAssignee: needsAssignee,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _AssigneeSummary extends StatelessWidget {
  const _AssigneeSummary({
    required this.index,
    required this.draft,
    required this.participants,
    required this.needsAssignee,
    required this.onChanged,
  });

  final int index;
  final _ItemDraft draft;
  final List<SplitParticipant> participants;
  final bool needsAssignee;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final nameOf = {for (final p in participants) p.id: p.name};
    final selected = [
      for (final p in participants)
        if (draft.assignees.contains(p.id)) p,
    ];
    final everyone = selected.isNotEmpty &&
        selected.length == participants.length;

    final String summary;
    if (selected.isEmpty) {
      summary = l10n.itemizedNeedsSomeone;
    } else if (everyone) {
      summary = '${l10n.itemizedEveryone} · ${participants.length}';
    } else if (selected.length == 1) {
      summary = l10n.itemizedForName(nameOf[selected.first.id] ?? selected.first.name);
    } else {
      summary = selected.map((p) => p.name).join(', ');
    }

    return GestureDetector(
      key: Key('itemized_assignees_$index'),
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        HapticService.lightClick();
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: context.colors.scaffoldBackground,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (_) => _AssignSheet(
            draft: draft,
            participants: participants,
          ),
        );
        onChanged();
      },
      child: Row(
        children: [
          if (selected.isNotEmpty) _MiniAvatarStack(participants: selected),
          if (selected.isNotEmpty) SizedBox(width: context.spacing.space8),
          Flexible(
            child: Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.sans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: needsAssignee
                    ? colors.error
                    : (everyone ? colors.primary : colors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniAvatarStack extends StatelessWidget {
  const _MiniAvatarStack({required this.participants});

  final List<SplitParticipant> participants;

  @override
  Widget build(BuildContext context) {
    const max = 4;
    final shown = participants.take(max).toList();
    return SizedBox(
      height: 20,
      width: 20.0 + (shown.length - 1) * 13,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            PositionedDirectional(
              start: i * 13.0,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.colors.cardSurface,
                    width: 1.5,
                  ),
                ),
                // #1168: colorKey = participant.id (== member userId).
                child: RAvatar(
                  name: shown[i].name,
                  size: 18,
                  colorKey: shown[i].id,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OwesRow extends StatelessWidget {
  const _OwesRow({
    required this.name,
    this.colorKey,
    required this.role,
    required this.owed,
    required this.currency,
    required this.showDivider,
  });

  final String name;

  /// Participant id (== member userId, #1168) — keys the avatar's palette
  /// slot on stable identity instead of the display name.
  final String? colorKey;

  final String? role;
  final Decimal owed;
  final String currency;
  final bool showDivider;

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
        children: [
          RAvatar(name: name, size: 28, colorKey: colorKey),
          SizedBox(width: context.spacing.space12),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                if (role != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    role!,
                    style: AppTypography.sans(
                      fontSize: 11,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: context.spacing.space12),
          RAmount(value: owed, currency: currency, size: 13),
        ],
      ),
    );
  }
}

/// Checkbox list to assign an item's [draft] to participants, with a one-tap
/// "Everyone" that toggles all on (the shared base). Mutates [draft.assignees]
/// in place and rebuilds locally; the caller refreshes the sheet on dismiss.
class _AssignSheet extends StatefulWidget {
  const _AssignSheet({required this.draft, required this.participants});

  final _ItemDraft draft;
  final List<SplitParticipant> participants;

  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final l10n = context.l10n;
    final all = widget.participants;
    final allOn =
        all.isNotEmpty && all.every((p) => widget.draft.assignees.contains(p.id));

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
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.space24),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.itemizedWhoHadThis,
                      style: AppTypography.displayOf(
                        context,
                        fontSize: 22,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  GestureDetector(
                    key: const Key('itemized_everyone'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticService.selection();
                      setState(() {
                        if (allOn) {
                          widget.draft.assignees.clear();
                        } else {
                          widget.draft.assignees
                            ..clear()
                            ..addAll(all.map((p) => p.id));
                        }
                      });
                    },
                    child: Padding(
                      padding: EdgeInsets.all(spacing.space4),
                      child: Text(
                        l10n.itemizedEveryone,
                        style: AppTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colors.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.space12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.symmetric(horizontal: spacing.space24),
                itemCount: all.length,
                itemBuilder: (context, i) {
                  final p = all[i];
                  final on = widget.draft.assignees.contains(p.id);
                  return InkWell(
                    key: Key('itemized_assign_tile_${p.id}'),
                    onTap: () {
                      HapticService.selection();
                      setState(() {
                        if (on) {
                          widget.draft.assignees.remove(p.id);
                        } else {
                          widget.draft.assignees.add(p.id);
                        }
                      });
                    },
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(vertical: spacing.space8),
                      child: Row(
                        children: [
                          Icon(
                            on ? Icons.check_box : Icons.check_box_outline_blank,
                            color: on ? colors.primary : colors.textSecondary,
                            size: 22,
                          ),
                          SizedBox(width: spacing.space12),
                          RAvatar(name: p.name, size: 32, colorKey: p.id),
                          SizedBox(width: spacing.space12),
                          Expanded(
                            child: Text(
                              p.name,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.sans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.space24,
                spacing.space12,
                spacing.space24,
                spacing.space20,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  key: const Key('itemized_assign_done'),
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.textOnPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    l10n.customSplitApply,
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
    );
  }
}

// ───────────────────────────────────── bill-level adjustments UI (#605)

/// The "Adjustments" section under Items: a header with "+ Add" and a card of
/// adjustment rows. Tapping a row opens the editor; the ✕ removes it.
class _AdjustmentsSection extends StatelessWidget {
  const _AdjustmentsSection({
    required this.adjDrafts,
    required this.participants,
    required this.currency,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  final List<_AdjustmentDraft> adjDrafts;
  final List<SplitParticipant> participants;
  final String currency;
  final VoidCallback onAdd;
  final ValueChanged<_AdjustmentDraft> onEdit;
  final ValueChanged<_AdjustmentDraft> onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ItemizedSectionHeader(
          label: l10n.adjustmentsHeader,
          action: l10n.adjustmentAddAction,
          actionKey: const Key('itemized_add_adjustment'),
          onAction: onAdd,
        ),
        if (adjDrafts.isNotEmpty) ...[
          SizedBox(height: spacing.space8),
          Container(
            decoration: BoxDecoration(
              color: colors.cardSurface,
              borderRadius: BorderRadius.circular(spacing.radiusLarge),
              boxShadow: context.shadows.raised,
            ),
            padding: EdgeInsets.symmetric(horizontal: spacing.space16),
            child: Column(
              children: [
                for (var i = 0; i < adjDrafts.length; i++)
                  _AdjustmentRow(
                    index: i,
                    draft: adjDrafts[i],
                    participants: participants,
                    currency: currency,
                    showDivider: i < adjDrafts.length - 1,
                    onEdit: () => onEdit(adjDrafts[i]),
                    onRemove: () => onRemove(adjDrafts[i]),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _AdjustmentRow extends StatelessWidget {
  const _AdjustmentRow({
    required this.index,
    required this.draft,
    required this.participants,
    required this.currency,
    required this.showDivider,
    required this.onEdit,
    required this.onRemove,
  });

  final int index;
  final _AdjustmentDraft draft;
  final List<SplitParticipant> participants;
  final String currency;
  final bool showDivider;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final isDiscount = draft.type == 'discount';
    final parsed = Decimal.tryParse(draft.amount.text) ?? Decimal.zero;
    final isAssigned =
        isDiscount && draft.allocation == 'assigned' && draft.participantIds.isNotEmpty;
    // Assigned discounts show a "who bears it" caption (subset names, same
    // style as item-assignee captions #605) instead of the spread label.
    final String subLabel;
    if (isAssigned) {
      final nameOf = {for (final p in participants) p.id: p.name};
      final names = [
        for (final id in draft.participantIds)
          if (nameOf[id] != null) nameOf[id]!,
      ].join(', ');
      subLabel = context.l10n.adjustmentDiscountBorneBy(names);
    } else if (isDiscount || draft.allocation == 'proportional') {
      subLabel = context.l10n.adjustmentAllocProportional;
    } else {
      subLabel = context.l10n.adjustmentAllocEqual;
    }

    return InkWell(
      key: Key('itemized_adjustment_$index'),
      onTap: onEdit,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: spacing.space12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: showDivider ? colors.rule : Colors.transparent,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _adjustmentTypeLabel(context, draft.type),
                    style: AppTypography.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subLabel,
                    style: AppTypography.sans(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: spacing.space8),
            // Signed amount: a discount subtracts (kept LTR so sign/code/amount
            // don't reorder under Arabic, matching the money-status convention).
            Text(
              isDiscount ? '−' : '+',
              textDirection: TextDirection.ltr,
              style: AppTypography.mono(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isDiscount ? colors.error : colors.primaryDark,
              ),
            ),
            const SizedBox(width: 2),
            RAmount(value: parsed, currency: currency, size: 13),
            IconButton(
              key: Key('itemized_adjustment_remove_$index'),
              tooltip: context.l10n.adjustmentRemove,
              icon: const Icon(Icons.close, size: 16),
              color: colors.textSecondary,
              visualDensity: VisualDensity.compact,
              onPressed: () {
                HapticService.selection();
                onRemove();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal editor for one adjustment: type chips, fixed-amount field, and the
/// allocation choice. An additive picks equal / by-item-share; a discount picks
/// proportional (default) or 'assigned' — which reveals a member multi-select
/// (#605). Mutates the passed [_AdjustmentDraft] in place; the sheet state
/// prunes it if left blank.
class _AddAdjustmentSheet extends StatefulWidget {
  const _AddAdjustmentSheet({
    required this.draft,
    required this.participants,
    required this.currency,
  });

  final _AdjustmentDraft draft;
  final List<SplitParticipant> participants;
  final String currency;

  @override
  State<_AddAdjustmentSheet> createState() => _AddAdjustmentSheetState();
}

class _AddAdjustmentSheetState extends State<_AddAdjustmentSheet> {
  static const _types = ['service', 'tax', 'tip', 'discount'];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final l10n = context.l10n;
    final draft = widget.draft;
    final isDiscount = draft.type == 'discount';
    final decimals =
        AppFormatters.currencyConfig[widget.currency]?.decimals ?? 3;

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
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.space24),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  l10n.adjustmentSheetTitle,
                  style: AppTypography.displayOf(
                    context,
                    fontSize: 22,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
            SizedBox(height: spacing.space16),
            // #1041 §4: a horizontal ListView tight-constrains every child's
            // cross axis to this box's height, so it must be ≥44dp for a
            // chip's opaque GestureDetector to reach the 44dp tap-target
            // floor — the visual pill stays compact via the chip's own
            // Center wrapper.
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: spacing.space24),
                children: [
                  for (final t in _types) ...[
                    _AdjustmentTypeChip(
                      type: t,
                      selected: draft.type == t,
                      onTap: () {
                        HapticService.selection();
                        setState(() {
                          draft.type = t;
                          if (t == 'discount') draft.allocation = 'proportional';
                        });
                      },
                    ),
                    SizedBox(width: spacing.space8),
                  ],
                ],
              ),
            ),
            SizedBox(height: spacing.space16),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.space24),
              child: TextField(
                key: const Key('adjustment_amount'),
                controller: draft.amount,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textDirection: TextDirection.ltr,
                inputFormatters: [
                  LocalizedDecimalTextInputFormatter(decimalDigits: decimals),
                ],
                style: AppTypography.mono(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
                decoration: InputDecoration(
                  labelText: l10n.adjustmentAmountLabel,
                  suffixText: widget.currency,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            SizedBox(height: spacing.space16),
            if (!isDiscount) ...[
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.space24),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    l10n.adjustmentSpreadHeader,
                    style: AppTypography.caption(
                      context,
                      fontSize: 10,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
              SizedBox(height: spacing.space8),
              _AllocationOption(
                optionKey: const Key('adjustment_alloc_equal'),
                label: l10n.adjustmentAllocEqual,
                selected: draft.allocation == 'equal',
                onTap: () {
                  HapticService.selection();
                  setState(() => draft.allocation = 'equal');
                },
              ),
              _AllocationOption(
                optionKey: const Key('adjustment_alloc_proportional'),
                label: l10n.adjustmentAllocProportional,
                selected: draft.allocation == 'proportional',
                onTap: () {
                  HapticService.selection();
                  setState(() => draft.allocation = 'proportional');
                },
              ),
            ] else ...[
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.space24),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    l10n.adjustmentSpreadHeader,
                    style: AppTypography.caption(
                      context,
                      fontSize: 10,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
              SizedBox(height: spacing.space8),
              // Proportional (default) — shared by what each person owes.
              _AllocationOption(
                optionKey: const Key('adjustment_alloc_proportional'),
                label: l10n.adjustmentAllocProportional,
                selected: draft.allocation != 'assigned',
                onTap: () {
                  HapticService.selection();
                  setState(() => draft.allocation = 'proportional');
                },
              ),
              // Assigned — borne only by a chosen subset (#605).
              _AllocationOption(
                optionKey: const Key('adjustment_alloc_assigned'),
                label: l10n.adjustmentDiscountAssignedLabel,
                selected: draft.allocation == 'assigned',
                onTap: () {
                  HapticService.selection();
                  setState(() => draft.allocation = 'assigned');
                },
              ),
              if (draft.allocation == 'assigned') ...[
                SizedBox(height: spacing.space12),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: spacing.space24),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      l10n.adjustmentDiscountWhoBears,
                      style: AppTypography.caption(
                        context,
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: spacing.space4),
                for (final p in widget.participants)
                  _AdjustmentAssigneeTile(
                    participant: p,
                    selected: draft.participantIds.contains(p.id),
                    onTap: () {
                      HapticService.selection();
                      setState(() {
                        if (draft.participantIds.contains(p.id)) {
                          draft.participantIds.remove(p.id);
                        } else {
                          draft.participantIds.add(p.id);
                        }
                      });
                    },
                  ),
              ],
            ],
            SizedBox(height: spacing.space20),
            Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.space24,
                0,
                spacing.space24,
                spacing.space20,
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  key: const Key('adjustment_done'),
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.textOnPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    l10n.adjustmentDone,
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
    );
  }
}

class _AdjustmentTypeChip extends StatelessWidget {
  const _AdjustmentTypeChip({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final String type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return GestureDetector(
      key: Key('adjustment_type_$type'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.space12,
            vertical: spacing.space8,
          ),
          decoration: BoxDecoration(
            color: selected
                ? colors.primary.withValues(alpha: 0.12)
                : colors.cardSurface,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: selected ? colors.primary : colors.rule2,
            ),
          ),
          child: Text(
            _adjustmentTypeLabel(context, type),
            style: AppTypography.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? colors.primaryDark : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// One member row in the assigned-discount picker (#605): checkbox + avatar +
/// name, mirroring the item-assignee tile pattern. Toggles the draft subset.
class _AdjustmentAssigneeTile extends StatelessWidget {
  const _AdjustmentAssigneeTile({
    required this.participant,
    required this.selected,
    required this.onTap,
  });

  final SplitParticipant participant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return InkWell(
      key: Key('adjustment_assign_tile_${participant.id}'),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.space24,
          vertical: spacing.space8,
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_box : Icons.check_box_outline_blank,
              color: selected ? colors.primary : colors.textSecondary,
              size: 22,
            ),
            SizedBox(width: spacing.space12),
            RAvatar(name: participant.name, size: 32, colorKey: participant.id),
            SizedBox(width: spacing.space12),
            Expanded(
              child: Text(
                participant.name,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.sans(
                  fontSize: 14,
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

class _AllocationOption extends StatelessWidget {
  const _AllocationOption({
    required this.optionKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Key optionKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return InkWell(
      key: optionKey,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.space24,
          vertical: spacing.space12,
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? colors.primary : colors.textSecondary,
              size: 20,
            ),
            SizedBox(width: spacing.space12),
            Text(
              label,
              style: AppTypography.sans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
