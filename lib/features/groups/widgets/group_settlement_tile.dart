import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/utils/bidi.dart';
import '../keys/group_keys.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../shared/widgets/directional_icon.dart';
import '../../../shared/widgets/falaj_fork.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../../../core/theme/tokens/typography_tokens.dart';

/// A card-style settlement tile showing payer → payee, amount, and a
/// collapsible per-event breakdown (D-04).
///
/// Converted to StatefulWidget to support expand/collapse state.
class GroupSettlementTile extends StatefulWidget {
  final String fromName;
  final String toName;

  /// Payer/recipient userIds (#1168) — key each avatar's palette slot on
  /// stable identity instead of the display name.
  final String? fromUserId;
  final String? toUserId;

  final Decimal amount;
  final String currency;
  final Map<String, Decimal> breakdown;

  /// #1204: resolves a [breakdown] key to its display label at render time.
  /// Null means the key IS the label (backward-compatible default) — keeps
  /// this widget usable standalone with a plain label-keyed map.
  final String Function(String key)? breakdownLabel;

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
    this.fromUserId,
    this.toUserId,
    required this.amount,
    required this.currency,
    required this.breakdown,
    this.breakdownLabel,
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

  AmountTone get _amountTone {
    if (widget.isYourAction) return AmountTone.rustText;
    if (widget.isCreditor) return AmountTone.sageText;
    return AmountTone.ink;
  }

  String get _subLabel {
    // #1216b: isolate names at the l10n arg (never the source prop). Renders as
    // a Semantics label only, so the wrap is harmless there but keeps the
    // 13-key contract uniform.
    if (widget.isYourAction) {
      return context.l10n.settleUpYouOwe(bidiIsolate(widget.toName));
    }
    if (widget.isCreditor) {
      return context.l10n.settleUpOwesYou(bidiIsolate(widget.fromName));
    }
    return context.l10n.settleUpOwes(
      bidiIsolate(widget.fromName),
      bidiIsolate(widget.toName),
    );
  }

  /// #282/#595: the debtor records a payment *made* ("Mark paid"), the creditor
  /// a payment *received* ("Mark received"), and any other member records on the
  /// group's behalf ("Record"). The write direction is identical — only the
  /// label differs. Cases are mutually exclusive: one transfer has one payer and
  /// one recipient, so the current user is at most one of them.
  String get _recordLabel {
    if (widget.isYourAction) return context.l10n.settleUpMarkPaid;
    if (widget.isCreditor) return context.l10n.settleUpMarkReceived;
    return context.l10n.settleUpRecordPayment;
  }

  @override
  Widget build(BuildContext context) {
    const spacing = AppSpacingTokens.standard;
    final captionTextDirection = Directionality.of(context);
    final compactFromName = _compactName(widget.fromName);
    final compactToName = _compactName(widget.toName);

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
                    RAvatar(
                      name: widget.fromName,
                      size: 36,
                      colorKey: widget.fromUserId,
                    ),
                    SizedBox(width: spacing.space12),
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // comp-8 (#900): structural rule2 fork, NOT brass —
                            // the connector is channel-work, so N tiles per
                            // screen don't breach the ≤1-full-fork usage law.
                            // Branches fan into the payee; the fork itself is
                            // the direction cue (mirrors via Directionality).
                            Positioned.fill(
                              child: Center(
                                child: SizedBox(
                                  height: 14,
                                  width: double.infinity,
                                  child: CustomPaint(
                                    painter: FalajForkPainter(
                                      color: context.colors.rule2,
                                      textDirection: Directionality.of(context),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: context.spacing.space8,
                                vertical: context.spacing.space4,
                              ),
                              decoration: BoxDecoration(
                                color: widget.isHighlighted
                                    ? context.colors.saffronTint
                                    : context.colors.cardSurface,
                                borderRadius: BorderRadius.circular(
                                  spacing.radiusSmall,
                                ),
                              ),
                              child: RAmount(
                                value: widget.amount,
                                currency: widget.currency,
                                size: 16,
                                weight: FontWeight.w700,
                                tone: _amountTone,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: spacing.space12),
                    RAvatar(
                      name: widget.toName,
                      size: 36,
                      colorKey: widget.toUserId,
                    ),
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
                              text: _captionName(
                                compactFromName,
                                captionTextDirection,
                              ),
                              semanticsLabel: compactFromName,
                              style: TextStyle(
                                color: context.colors.ink2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.symmetric(
                                  horizontal: 4,
                                ),
                                child: DirectionalIcon(
                                  Iconsax.arrow_right_1,
                                  size: 12,
                                  color: context.colors.textSecondary,
                                ),
                              ),
                            ),
                            TextSpan(
                              text: _captionName(
                                compactToName,
                                captionTextDirection,
                              ),
                              semanticsLabel: compactToName,
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
                          tapTargetSize: MaterialTapTargetSize.padded,
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          _recordLabel,
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
                                          // #1204: resolved from the (possibly
                                          // opaque, e.g. a raw eventId) key at
                                          // render time — never baked into
                                          // the map's key, so two entries
                                          // sharing a label still render as
                                          // two distinct rows.
                                          widget.breakdownLabel?.call(e.key) ??
                                              e.key,
                                          style: AppTypography.sans(
                                            fontSize: 12,
                                            color: context.colors.textSecondary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      RAmount(
                                        value: e.value,
                                        currency: widget.currency,
                                        size: 12,
                                        tone: AmountTone.muted,
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

  /// FSI/PDI keeps each name in its own bidi run so the paragraph orders
  /// payer and payee by UI direction instead of the names' script.
  /// LTR paragraphs order isolated runs left-to-right, keeping Latin text
  /// byte-for-byte unchanged while pinning Arabic to logical order.
  String _captionName(String name, TextDirection textDirection) {
    return '\u2068$name\u2069';
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
