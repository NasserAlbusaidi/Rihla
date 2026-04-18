import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/utils/formatters.dart';
import '../keys/group_keys.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

/// A card-style settlement tile showing payer → payee, amount, and a
/// collapsible per-event breakdown (D-04).
///
/// Converted to StatefulWidget to support expand/collapse state.
class GroupSettlementTile extends StatefulWidget {
  final String fromName;
  final String toName;
  final Decimal amount;
  final String currency;
  final Map<String, Decimal> breakdown;

  /// When true the tile belongs to the "You Owe" tab — amount shown in errorText.
  final bool isYourAction;

  /// When true the tile belongs to the "Owed to You" tab — amount shown in successText.
  final bool isCreditor;

  final bool isHighlighted;
  final GlobalKey? tileKey;
  final VoidCallback? onRecord;

  const GroupSettlementTile({
    super.key,
    required this.fromName,
    required this.toName,
    required this.amount,
    required this.currency,
    required this.breakdown,
    required this.isYourAction,
    this.isCreditor = false,
    this.isHighlighted = false,
    this.tileKey,
    this.onRecord,
  });

  @override
  State<GroupSettlementTile> createState() => _GroupSettlementTileState();
}

class _GroupSettlementTileState extends State<GroupSettlementTile> {
  bool _isExpanded = false;

  Color get _amountColor {
    if (widget.isYourAction) return context.colors.errorText;
    if (widget.isCreditor) return context.colors.successText;
    return context.colors.textPrimary;
  }

  String get _subLabel {
    if (widget.isYourAction) return 'You owe ${widget.toName}';
    if (widget.isCreditor) return '${widget.fromName} owes you';
    return '${widget.fromName} owes ${widget.toName}';
  }

  @override
  Widget build(BuildContext context) {
    const spacing = AppSpacingTokens.standard;

    return Container(
      key: widget.tileKey,
      margin: EdgeInsets.only(bottom: spacing.space12),
      decoration: BoxDecoration(
        color: widget.isHighlighted
            ? context.colors.primary.withValues(alpha: 0.05)
            : context.colors.cardSurface,
        borderRadius: BorderRadius.circular(spacing.radiusLarge),
        boxShadow: context.shadows.raised,
        border: Border.all(
          color: widget.isHighlighted
              ? context.colors.primary.withValues(alpha: 0.2)
              : context.colors.border.withValues(alpha: 0.5),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(spacing.radiusLarge),
        child: InkWell(
          onTap: widget.breakdown.isNotEmpty
              ? () => setState(() => _isExpanded = !_isExpanded)
              : null,
          borderRadius: BorderRadius.circular(spacing.radiusLarge),
          child: Padding(
            padding: EdgeInsets.all(spacing.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Main row: avatar stack | names column | amount column | chevron
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Overlapping avatar pair (40dp each, -12dp offset)
                    SizedBox(
                      width: 60,
                      height: 40,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            child: _buildAvatar(widget.fromName, isPayer: true),
                          ),
                          Positioned(
                            left: 20,
                            child: _buildAvatar(widget.toName, isPayer: false),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: spacing.space12),
                    // Names + sub-label column
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: TextSpan(
                              style: TextStyle(
                                fontSize: 14,
                                color: context.colors.textPrimary,
                              ),
                              children: [
                                TextSpan(
                                  text: widget.fromName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(
                                  text: ' → ',
                                  style: TextStyle(
                                    // textMuted-decorative-justified: arrow glyph connecting payer → payee names, purely visual separator
                                    color: context.colors.textMuted,
                                  ),
                                ),
                                TextSpan(
                                  text: widget.toName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: spacing.space4),
                          Text(
                            _subLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.colors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: spacing.space8),
                    // Amount + currency + chevron
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          AppFormatters.formatCurrency(
                            widget.amount,
                            widget.currency,
                          ),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: _amountColor,
                          ),
                        ),
                        SizedBox(height: spacing.space4),
                        if (widget.breakdown.isNotEmpty)
                          AnimatedRotation(
                            turns: _isExpanded ? 0.5 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            child: Icon(
                              Iconsax.arrow_down_1,
                              size: 16,
                              // textMuted-decorative-justified: expand/collapse chevron affordance — meaning is carried by the state change, icon is decorative
                              color: context.colors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                // Collapsible per-event breakdown
                if (widget.breakdown.isNotEmpty)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: _isExpanded
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(height: spacing.space12),
                              Divider(
                                height: 1,
                                thickness: 1,
                                color: context.colors.border
                                    .withValues(alpha: 0.5),
                              ),
                              SizedBox(height: spacing.space8),
                              ...widget.breakdown.entries.map(
                                (e) => Padding(
                                  padding: EdgeInsets.only(
                                    bottom: spacing.space4,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          e.key,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color:
                                                context.colors.textSecondary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        AppFormatters.formatCurrency(
                                          e.value,
                                          widget.currency,
                                        ),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color:
                                              context.colors.textSecondary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),

                // Record Payment button
                if (widget.onRecord != null) ...[
                  SizedBox(height: spacing.space12),
                  SizedBox(
                    width: double.infinity,
                    height: spacing.buttonHeight,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: context.colors.primaryGradient,
                        borderRadius: BorderRadius.circular(spacing.radiusMedium),
                      ),
                      child: ElevatedButton(
                        key: GroupKeys.settleUpRecordPaymentButton,
                        onPressed: widget.onRecord,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          padding: EdgeInsets.symmetric(
                            vertical: spacing.space16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(spacing.radiusMedium),
                          ),
                        ),
                        child: const Text(
                          'Record Payment',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(String name, {required bool isPayer}) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isPayer
            ? context.colors.primary.withValues(alpha: 0.15)
            : context.colors.inputFill,
        shape: BoxShape.circle,
        border: Border.all(
          color: isPayer
              ? context.colors.primary.withValues(alpha: 0.4)
              : context.colors.border,
          width: isPayer ? 2 : 1,
        ),
        boxShadow: context.shadows.raised,
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isPayer
                ? context.colors.primary
                : context.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
