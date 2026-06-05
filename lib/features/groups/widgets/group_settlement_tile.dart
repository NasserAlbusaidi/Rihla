import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
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
    if (widget.isYourAction) return context.l10n.settleUpYouOwe(widget.toName);
    if (widget.isCreditor) return context.l10n.settleUpOwesYou(widget.fromName);
    return context.l10n.settleUpOwes(widget.fromName, widget.toName);
  }

  @override
  Widget build(BuildContext context) {
    const spacing = AppSpacingTokens.standard;

    return Container(
      key: widget.tileKey,
      margin: EdgeInsets.only(bottom: spacing.space12),
      decoration: BoxDecoration(
        color: widget.isHighlighted
            ? context.colors.saffronTint
            : context.colors.cardSurface,
        borderRadius: BorderRadius.circular(spacing.radiusLarge),
        boxShadow: context.shadows.raised,
        border: Border.all(
          color: widget.isHighlighted
              ? context.colors.primary.withValues(alpha: 0.28)
              : context.colors.rule,
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
                Row(
                  children: [
                    _buildAvatar(widget.fromName, isPayer: true),
                    SizedBox(width: spacing.space12),
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _TransferRailPainter(
                                  color: context.colors.rule2,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: widget.isHighlighted
                                    ? context.colors.saffronTint
                                    : context.colors.cardSurface,
                                borderRadius: BorderRadius.circular(
                                  spacing.radiusSmall,
                                ),
                              ),
                              child: Text(
                                AppFormatters.formatCurrency(
                                  widget.amount,
                                  widget.currency,
                                ),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: _amountColor,
                                ),
                              ),
                            ),
                            Positioned(
                              right: 0,
                              child: Icon(
                                Iconsax.arrow_right_1,
                                size: 14,
                                // textMuted-decorative-justified: transfer direction arrow is decorative; payer/payee text carries the meaning.
                                color: context.colors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: spacing.space12),
                    _buildAvatar(widget.toName, isPayer: false),
                  ],
                ),
                SizedBox(height: spacing.space12),
                Row(
                  children: [
                    Expanded(
                      child: RichText(
                        overflow: TextOverflow.ellipsis,
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.textSecondary,
                          ),
                          children: [
                            TextSpan(
                              text: _compactName(widget.fromName),
                              style: TextStyle(
                                color: context.colors.ink2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(
                              text: ' -> ',
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            TextSpan(
                              text: _compactName(widget.toName),
                              style: TextStyle(
                                color: context.colors.ink2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (widget.breakdown.isNotEmpty)
                      AnimatedRotation(
                        turns: _isExpanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          Iconsax.arrow_down_1,
                          size: 16,
                          // textMuted-decorative-justified: expand/collapse chevron is a visual affordance for the hidden event breakdown.
                          color: context.colors.textMuted,
                        ),
                      ),
                    if (widget.onRecord != null) ...[
                      SizedBox(width: spacing.space8),
                      TextButton(
                        key: GroupKeys.settleUpRecordPaymentButton,
                        onPressed: widget.onRecord,
                        style: TextButton.styleFrom(
                          backgroundColor: context.colors.saffronTint,
                          foregroundColor: context.colors.primaryDark,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          minimumSize: const Size(0, 40),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          context.l10n.settleUpMarkPaid,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: 1.22,
                            leadingDistribution: TextLeadingDistribution.even,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Semantics(label: _subLabel, child: const SizedBox.shrink()),

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
                                color: context.colors.border.withValues(
                                  alpha: 0.5,
                                ),
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
                                            color: context.colors.textSecondary,
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
                                          color: context.colors.textSecondary,
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(String name, {required bool isPayer}) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isPayer ? context.colors.saffronTint : context.colors.cardSoft,
        shape: BoxShape.circle,
        // #147: uniform border (matches _MiniAvatar). Payer/payee is carried by
        // the background tint + the names row below — not a redundant ring color.
        border: Border.all(color: context.colors.rule2),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: isPayer ? context.colors.primaryDark : context.colors.ink2,
          ),
        ),
      ),
    );
  }

  /// Compact label for the direction line: the first token of the base name,
  /// with the same-name disambiguation discriminator (` (#last4)`, #196)
  /// re-appended when the resolver added one. A plain first-name split dropped
  /// it, collapsing two colliding members to "Sam -> Sam" (#263). The pattern
  /// mirrors `MemberNameResolver.stripDiscriminator`.
  String _compactName(String name) {
    final match = RegExp(r' \(#[^)]*\)$').firstMatch(name);
    final discriminator = match?.group(0) ?? '';
    final base = name.substring(0, name.length - discriminator.length);
    final parts = base.trim().split(RegExp(r'\s+'));
    final first = parts.isEmpty ? base : parts.first;
    return '$first$discriminator';
  }
}

class _TransferRailPainter extends CustomPainter {
  const _TransferRailPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dashWidth = 5.0;
    const dashSpace = 4.0;
    var startX = 0.0;
    final y = size.height / 2;

    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, y),
        Offset((startX + dashWidth).clamp(0, size.width), y),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _TransferRailPainter oldDelegate) =>
      oldDelegate.color != color;
}
