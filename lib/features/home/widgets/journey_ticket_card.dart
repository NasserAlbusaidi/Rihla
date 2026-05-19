import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/utils/localized_dates.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/cover_art.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../providers/active_journeys_provider.dart';

/// "Ticket stub"-styled card for one journey on the home Active Journeys
/// strip. Cover-art band on top, dashed perforation separator, content below
/// with title, member stack, and trailing balance.
class JourneyTicketCard extends StatelessWidget {
  const JourneyTicketCard({
    super.key,
    required this.entry,
    this.width = 220,
    this.onTap,
  });

  /// The journey to render.
  final ActiveJourneyEntry entry;

  /// Card width. Wireframe default 220px.
  final double width;

  /// Tap handler — typically routes to the event hub.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dateLabel = _formatDates(context, entry.startDate, entry.endDate);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: colors.cardSurface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: context.shadows.raised,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover art band.
            SizedBox(
              height: 88,
              width: double.infinity,
              child: Stack(
                children: [
                  Positioned.fill(child: CoverArt.forEventType(entry.type)),
                  if (dateLabel != null)
                    Positioned.directional(
                      textDirection: Directionality.of(context),
                      top: 8,
                      start: 10,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            color: colors.textPrimary.withValues(alpha: 0.5),
                            child: Text(
                              dateLabel.toUpperCase(),
                              style: AppTypography.mono(
                                fontSize: 9,
                                color: Colors.white,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Dashed perforation with two paper-colored punch holes at the
            // edges — the ticket-stub signature. Holes extend past the row's
            // own bounds and the parent card's antiAlias clip turns them into
            // half-moon bites at the card's vertical edges.
            _Perforation(
              ruleColor: colors.rule2,
              holeColor: colors.scaffoldBackground,
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.display(
                      fontSize: 18,
                      color: colors.textPrimary,
                      letterSpacing: -0.2,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: entry.memberNames.isEmpty
                            ? const SizedBox.shrink()
                            : RAvatarStack(
                                names: entry.memberNames,
                                size: 20,
                                max: 3,
                              ),
                      ),
                      RAmount(value: entry.userBalance, size: 14, sign: true),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Mar 14 — Mar 22" / "Mar 14" / "ending Mar 22" / null.
  static String? _formatDates(
    BuildContext context,
    DateTime? start,
    DateTime? end,
  ) {
    if (start != null && end != null) {
      return formatDateRangeShort(context, start, end);
    }
    if (start != null) return formatShortMonthDay(context, start);
    if (end != null) {
      return context.l10n.groupEventEnds(formatShortMonthDay(context, end));
    }
    return null;
  }
}

// ────────── Perforation (dashed rule + edge punch holes) ──────────

/// Dashed perforation strip with two paper-colored circular bites at the
/// card's left and right edges. The 12×12 circles sit half-out of the row
/// (centered on the vertical card edge) and the parent card's antiAlias clip
/// trims them to half-moons — the visual signature of a torn ticket stub.
class _Perforation extends StatelessWidget {
  const _Perforation({required this.ruleColor, required this.holeColor});

  final Color ruleColor;

  /// Should be the surface behind the card (the scaffold paper) so the bite
  /// reads as "the paper showing through".
  final Color holeColor;

  @override
  Widget build(BuildContext context) {
    const holeSize = 12.0;
    return SizedBox(
      height: 1,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _DashedRulePainter(color: ruleColor)),
          ),
          Positioned.directional(
            textDirection: Directionality.of(context),
            start: -holeSize / 2,
            top: -holeSize / 2 + 0.5,
            child: _PunchHole(size: holeSize, color: holeColor),
          ),
          Positioned.directional(
            textDirection: Directionality.of(context),
            end: -holeSize / 2,
            top: -holeSize / 2 + 0.5,
            child: _PunchHole(size: holeSize, color: holeColor),
          ),
        ],
      ),
    );
  }
}

class _PunchHole extends StatelessWidget {
  const _PunchHole({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _DashedRulePainter extends CustomPainter {
  const _DashedRulePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dashWidth = 4.0;
    const gap = 3.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0.5), Offset(x + dashWidth, 0.5), paint);
      x += dashWidth + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRulePainter old) => old.color != color;
}
