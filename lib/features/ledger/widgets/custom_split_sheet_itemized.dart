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

class _ItemizedBody extends StatelessWidget {
  const _ItemizedBody({
    super.key,
    required this.drafts,
    required this.participants,
    required this.currency,
    required this.preview,
    required this.draftValid,
    required this.onChanged,
    required this.onAddItem,
    required this.onRemoveItem,
  });

  final List<_ItemDraft> drafts;
  final List<SplitParticipant> participants;
  final String currency;

  /// Live per-person owed from the currently-valid drafts (computed by the
  /// sheet state; excludes rows missing an amount/assignee).
  final Map<String, Decimal> preview;
  final bool Function(_ItemDraft draft) draftValid;
  final VoidCallback onChanged;
  final VoidCallback onAddItem;
  final ValueChanged<_ItemDraft> onRemoveItem;

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
            style: AppTypography.mono(
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
          if (selected.isNotEmpty)
            _MiniAvatarStack(names: [for (final p in selected) p.name]),
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
  const _MiniAvatarStack({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    const max = 4;
    final shown = names.take(max).toList();
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
                child: RAvatar(name: shown[i], size: 18),
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
    required this.role,
    required this.owed,
    required this.currency,
    required this.showDivider,
  });

  final String name;
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
          RAvatar(name: name, size: 28),
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
                      style: AppTypography.display(
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
                          RAvatar(name: p.name, size: 32),
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
