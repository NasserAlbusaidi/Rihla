import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/activity_log_model.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../core/theme/tokens/color_tokens.dart';

class TimelineCard extends StatelessWidget {
  final ActivityLog log;
  final bool isLast;

  const TimelineCard({super.key, required this.log, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    final bool isDeleted =
        log.logText.toLowerCase().contains('deleted') ||
        (log.metadata['is_deleted'] == true);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline Line & Connector
          SizedBox(
            width: 50,
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.transparent),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _buildAvatarOrIcon(),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: Colors.grey.withValues(alpha: 0.2),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
              ],
            ),
          ),

          // Content Card
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 0, 24),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDeleted
                    ? Colors.red.withValues(alpha: 0.05)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDeleted
                      ? Colors.red.withValues(alpha: 0.2)
                      : Colors.grey.shade200,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: Category Icon + Description + Time
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _getCategoryIcon(),
                        size: 16,
                        color: _getCategoryColor(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: _buildRichLogText(context, isDeleted)),
                      if (isDeleted)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: Colors.red.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Text(
                            'DELETED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ),
                    ],
                  ),

                  // Metadata / Diff
                  if (log.metadata.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildMetadataDiff(context),
                  ],

                  // Footer: Time
                  const SizedBox(height: 6),
                  Text(
                    timeago.format(log.createdAt),
                    style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarOrIcon() {
    if (log.actorAvatar != null) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: log.actorAvatar!,
          fit: BoxFit.cover,
          placeholder: (context, url) => Center(
            child: Icon(_getCategoryIcon(), size: 16, color: Colors.grey),
          ),
          errorWidget: (context, url, error) => Center(
            child: Icon(_getCategoryIcon(), size: 16, color: Colors.grey),
          ),
        ),
      );
    }

    // Fallback: Initials or Icon
    if (log.actorName != null && log.actorName!.isNotEmpty) {
      return Center(
        child: Text(
          log.actorName![0].toUpperCase(),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: _getCategoryColor(),
          ),
        ),
      );
    }

    return Center(
      child: Icon(_getCategoryIcon(), size: 18, color: _getCategoryColor()),
    );
  }

  Widget _buildRichLogText(BuildContext context, bool isDeleted) {
    // Simple bolding strategy: words matching actorName, targetName, or keywords
    // Since we don't have perfect string ranges from the DB, we split by space and matched words.
    // This is a naive implementation but fits the "render text" requirement.

    final words = log.logText.split(' ');
    final spans = <InlineSpan>[];

    // Keywords to bold (from spec)
    final keywords = {
      'Fuel',
      'SUV',
      'Permit',
      'Money',
      'Gear',
      'Paid',
      'Added',
      'Created',
      'Deleted',
    };

    for (var word in words) {
      // Clean word of punctuation for matching
      final cleanWord = word.replaceAll(RegExp(r'[^\w\s]'), '');

      TextStyle style = TextStyle(
        fontSize: 14,
        color: AppColorTokens.light.textPrimary,
        decoration: isDeleted ? TextDecoration.lineThrough : null,
        fontFamily: 'NotoSans', // Requested font
      );

      bool isBold = false;
      bool isSemiBold = false;

      // Check if actor name part
      if (log.actorName != null && log.actorName!.contains(cleanWord)) {
        isBold = true;
      }
      // Check keyword
      if (keywords.contains(cleanWord)) {
        isSemiBold = true;
      }

      if (isBold) {
        style = style.copyWith(fontWeight: FontWeight.bold);
      } else if (isSemiBold) {
        style = style.copyWith(fontWeight: FontWeight.w600);
      }

      spans.add(TextSpan(text: '$word ', style: style));
    }

    return RichText(text: TextSpan(children: spans));
  }

  Widget _buildMetadataDiff(BuildContext context) {
    if (log.metadata.containsKey('old_amount') &&
        log.metadata.containsKey('new_amount')) {
      final oldVal = log.metadata['old_amount'];
      final newVal = log.metadata['new_amount'];

      // Determine if increase or decrease (assuming numeric)
      // If strings, just neutral
      bool isIncrease = true; // defaulting
      try {
        final oldNum = double.parse(oldVal.toString());
        final newNum = double.parse(newVal.toString());
        isIncrease = newNum > oldNum;
      } catch (e) {
        /* ignore */
      }

      final diffColor = isIncrease
          ? Colors.green
          : Colors.red; // Emerald/Rose roughly

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey[50], // Very light wash
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$oldVal',
              style: const TextStyle(
                decoration: TextDecoration.lineThrough,
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 12,
                color: Colors.grey[400],
              ),
            ),
            Text(
              '$newVal',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: diffColor,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Color _getCategoryColor() {
    // Money (Green/Emerald)
    // Gear (Orange/Amber)
    // Docs (Purple/Indigo)
    // Logistics (Blue/Sky)
    switch (log.category) {
      case 'MONEY':
        return Colors.green; // Emerald equivalent
      case 'GEAR':
        return Colors.amber;
      case 'DOCS':
        return Colors.indigo;
      case 'LOGISTICS':
        return Colors.lightBlue; // Sky equivalent
      default:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon() {
    switch (log.category) {
      case 'MONEY':
        return Icons.payments_outlined;
      case 'GEAR':
        return Icons.hiking_outlined;
      case 'DOCS':
        return Icons.folder_shared_outlined;
      case 'LOGISTICS':
        return Icons.hub_outlined; // Using hub as requested
      default:
        return Icons.circle_outlined;
    }
  }
}
