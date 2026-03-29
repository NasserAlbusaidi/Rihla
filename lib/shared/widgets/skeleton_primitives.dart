import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Composable skeleton building blocks for content-aware loading placeholders.
///
/// All primitives use [AppColors.surface] as fill color. The shimmer animation
/// is handled by the parent [Shimmer.fromColors] in [SkeletonLoader] — children
/// only need an opaque fill.
///
/// See [SkeletonLoader] for named factory variants that assemble these primitives
/// into screen-specific layouts.

/// A circular skeleton placeholder.
///
/// Use for avatar circles, icons, and round indicators.
class SkeletonCircle extends StatelessWidget {
  /// The diameter of the circle.
  final double size;

  const SkeletonCircle({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// A rectangular bar skeleton placeholder with rounded corners.
///
/// Use for text lines, labels, and single-line content.
class SkeletonBar extends StatelessWidget {
  /// The width of the bar.
  final double width;

  /// The height of the bar. Defaults to 14.0.
  final double height;

  /// Custom border radius. Defaults to [AppColors.radiusSmall] (8dp).
  final double? borderRadius;

  const SkeletonBar({
    super.key,
    required this.width,
    this.height = 14.0,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(borderRadius ?? AppColors.radiusSmall),
      ),
    );
  }
}

/// A rectangular block skeleton placeholder with rounded corners.
///
/// Use for card areas, buttons, images, and multi-line regions.
/// Distinguished from [SkeletonBar] by having a required height parameter
/// and defaulting to [AppColors.radiusMedium] border radius.
class SkeletonBlock extends StatelessWidget {
  /// The width of the block.
  final double width;

  /// The height of the block.
  final double height;

  /// Custom border radius. Defaults to [AppColors.radiusMedium] (12dp).
  final double? borderRadius;

  const SkeletonBlock({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(borderRadius ?? AppColors.radiusMedium),
      ),
    );
  }
}

/// A row skeleton placeholder combining a circle avatar and text bars.
///
/// Use for list items with avatar + name/subtitle layout.
class SkeletonRow extends StatelessWidget {
  /// Size of the circle avatar.
  final double circleSize;

  /// Width of the primary (larger) bar.
  final double barWidth;

  /// Height of the primary bar.
  final double barHeight;

  /// Width of the secondary (smaller) bar.
  final double smallBarWidth;

  /// Height of the secondary bar.
  final double smallBarHeight;

  /// Gap between the circle and the text column.
  final double gap;

  const SkeletonRow({
    super.key,
    this.circleSize = 40,
    this.barWidth = 140,
    this.barHeight = 14,
    this.smallBarWidth = 80,
    this.smallBarHeight = 12,
    this.gap = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SkeletonCircle(size: circleSize),
        SizedBox(width: gap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBar(width: barWidth, height: barHeight),
              const SizedBox(height: 6),
              SkeletonBar(width: smallBarWidth, height: smallBarHeight),
            ],
          ),
        ),
      ],
    );
  }
}

/// A full-width card skeleton placeholder with rounded corners.
///
/// Use as a generic block placeholder for card-shaped content.
class SkeletonCard extends StatelessWidget {
  /// The height of the card.
  final double height;

  /// Custom border radius. Defaults to [AppColors.radiusLarge] (16dp).
  final double? borderRadius;

  const SkeletonCard({
    super.key,
    this.height = 72,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(borderRadius ?? AppColors.radiusLarge),
      ),
    );
  }
}
