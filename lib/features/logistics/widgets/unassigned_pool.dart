import 'package:flutter/material.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../trip/models/trip_model.dart';
import '../models/sub_group_model.dart';

/// Horizontal scrollable pool of unassigned [Participant]s.
///
/// Each avatar is wrapped in a [Draggable] so the user can drag a participant
/// onto a [SubgroupCard] [DragTarget]. When the pool is empty this widget
/// renders nothing ([SizedBox.shrink]).
class UnassignedPool extends StatelessWidget {
  final List<Participant> unassigned;
  final SubGroupType type;

  const UnassignedPool({
    super.key,
    required this.unassigned,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    if (unassigned.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              const Text(
                'UNASSIGNED PERSONNEL',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: AppColors.textMuted,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${unassigned.length} LEFT',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: unassigned.length,
            itemBuilder: (context, index) {
              final p = unassigned[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Draggable<Participant>(
                  data: p,
                  feedback: _buildPoolItem(p, isFeedback: true),
                  childWhenDragging: Opacity(
                    opacity: 0.3,
                    child: _buildPoolItem(p),
                  ),
                  onDragStarted: HapticService.selection,
                  child: _buildPoolItem(p),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPoolItem(Participant p, {bool isFeedback = false}) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            boxShadow: isFeedback
                ? AppColors.cardShadowLarge
                : AppColors.cardShadow,
            border: Border.all(color: AppColors.surfaceLight, width: 2),
          ),
          child: Center(
            child: p.avatarUrl != null
                ? ClipOval(
                    child: Image.network(p.avatarUrl!, fit: BoxFit.cover),
                  )
                : Text(
                    (p.displayName ?? 'U')[0].toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 60,
          child: Text(
            (p.displayName?.split(' ')[0] ?? 'UNK').toUpperCase(),
            style: const TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w900,
              color: AppColors.textMuted,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
