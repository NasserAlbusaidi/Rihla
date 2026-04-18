import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../ledger/models/expense_model.dart';
import '../keys/group_keys.dart';

/// Expandable card showing a group member's net balance and per-event breakdown.
///
/// Per UI-SPEC Screen 3 (D-13, D-14, D-22):
/// - D-13: Accordion pattern — parent manages which card is expanded.
/// - D-14: Per-event rows are tappable and navigate to the event's LedgerScreen.
/// - D-22 entry point 2: "Settle" button appears in expanded state when
///   balance is non-zero; calls [onSettleUpTap].
class GroupMemberBalanceCard extends StatefulWidget {
  /// The member's balance summary.
  final UserBalance balance;

  /// Per-event net balances: eventId → net balance for this member.
  final Map<String, Decimal> perEventBreakdown;

  /// Event names: eventId → human-readable event name.
  final Map<String, String> eventNames;

  /// Currency code, typically 'OMR'.
  final String currency;

  /// Whether this card is currently expanded (accordion control from parent).
  final bool isExpanded;

  /// Called with the new expanded state when the user taps the header row.
  final ValueChanged<bool> onExpandChanged;

  /// Called when the user taps a per-event row (D-14).
  final void Function(String eventId)? onEventTap;

  /// Called when the user taps the "Settle" button (D-22 entry point 2).
  /// Null hides the button.
  final VoidCallback? onSettleUpTap;

  const GroupMemberBalanceCard({
    super.key,
    required this.balance,
    required this.perEventBreakdown,
    required this.eventNames,
    required this.currency,
    required this.isExpanded,
    required this.onExpandChanged,
    this.onEventTap,
    this.onSettleUpTap,
  });

  @override
  State<GroupMemberBalanceCard> createState() => _GroupMemberBalanceCardState();
}

class _GroupMemberBalanceCardState extends State<GroupMemberBalanceCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _chevronController;
  late Animation<double> _chevronRotation;

  @override
  void initState() {
    super.initState();
    _chevronController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: widget.isExpanded ? 1.0 : 0.0,
    );
    _chevronRotation = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _chevronController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didUpdateWidget(GroupMemberBalanceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        _chevronController.forward();
      } else {
        _chevronController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _chevronController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final net = widget.balance.netBalance;
    final isSettled = net == Decimal.zero;
    final isOwed = net > Decimal.zero;

    return Container(
      decoration: BoxDecoration(
        color: widget.isExpanded
            ? context.colors.selectionFill
            : context.colors.cardSurface,
        borderRadius: BorderRadius.circular(
          context.spacing.radiusLarge,
        ),
        border: Border.all(color: context.colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // --- Collapsed header row ---
          InkWell(
            onTap: () => widget.onExpandChanged(!widget.isExpanded),
            borderRadius: BorderRadius.circular(
              context.spacing.radiusLarge,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    // Member name
                    Expanded(
                      child: Text(
                        widget.balance.displayName ?? widget.balance.participantId,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),

                    // Net balance amount + settled badge
                    if (isSettled) ...[
                      Text(
                        '0.000 OMR',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        key: GroupKeys.settledBadge,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: context.colors.inputFill,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Settled',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ] else ...[
                      Text(
                        AppFormatters.formatCurrency(net.abs(), widget.currency),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isOwed
                          ? context.colors.successText
                          : context.colors.errorText,
                        ),
                      ),
                    ],

                    const SizedBox(width: 8),

                    // Expand chevron
                    RotationTransition(
                      turns: _chevronRotation,
                      child: Icon(
                        Iconsax.arrow_down_1,
                        size: 16,
                        // textMuted-decorative-justified: expand/collapse chevron affordance — meaning is carried by the state change, icon is decorative
                        color: context.colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // --- Expanded section ---
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            sizeCurve: Curves.easeOutCubic,
            firstChild: const SizedBox.shrink(),
            secondChild: _buildExpandedSection(net, isSettled),
            crossFadeState: widget.isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedSection(Decimal net, bool isSettled) {
    final showSettleButton =
        !isSettled && widget.onSettleUpTap != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Divider
        Divider(height: 1, thickness: 1, color: context.colors.border),

        // Per-event rows
        ...widget.perEventBreakdown.entries.map((entry) {
          final eventId = entry.key;
          final eventNet = entry.value;
          final eventName = widget.eventNames[eventId] ?? eventId;
          final eventIsOwed = eventNet > Decimal.zero;
          final sign = eventIsOwed ? '+' : '-';
          final absAmount =
              AppFormatters.formatCurrency(eventNet.abs(), widget.currency);

          return InkWell(
            onTap: widget.onEventTap != null
                ? () => widget.onEventTap!(eventId)
                : null,
            child: Container(
              color: context.colors.inputFill,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      eventName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    '$sign$absAmount',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: eventIsOwed
                          ? context.colors.successText
                          : context.colors.errorText,
                    ),
                  ),
                  if (widget.onEventTap != null) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Iconsax.arrow_right_3,
                      size: 14,
                      // textMuted-decorative-justified: trailing chevron indicating tappable row, redundant with the gesture handler
                      color: context.colors.textMuted,
                    ),
                  ],
                ],
              ),
            ),
          );
        }),

        // Settle button (D-22 entry point 2)
        if (showSettleButton)
          Padding(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: 8,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: GroupKeys.settleButton,
                onPressed: widget.onSettleUpTap,
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Settle',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.colors.primary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
