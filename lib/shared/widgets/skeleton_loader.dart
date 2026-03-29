import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/theme/app_theme.dart';
import 'skeleton_primitives.dart';

/// Reusable skeleton loading placeholders.
///
/// Named factory variants produce content-aware skeletons that mirror real
/// widget layouts, preventing layout jump when data loads.
///
/// All variants wrap their children in [Shimmer.fromColors] using warm-neutral
/// AppColors tokens:
/// - baseColor: [AppColors.surfaceLight] (#F3F4F6)
/// - highlightColor: [AppColors.surface] (#F8F9FA)
///
/// ## Named factories (content-aware)
/// - [SkeletonLoader.dashboardHero] — balance hero card + stats row
/// - [SkeletonLoader.eventCard] — event list card (icon + title + trailing amount)
/// - [SkeletonLoader.groupList] — group list row (avatar + text bars)
/// - [SkeletonLoader.expenseList] — expense row (avatar + two lines + trailing)
/// - [SkeletonLoader.gearList] — gear item (checkbox + name + assignee)
/// - [SkeletonLoader.generic] — plain card fallback
///
/// ## Backward-compatible factories (preserved)
/// - [SkeletonLoader.cardList] — delegates to generic
/// - [SkeletonLoader.documentList] — document card placeholder
class SkeletonLoader extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  const SkeletonLoader({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  // ---------------------------------------------------------------------------
  // Content-aware named factories
  // ---------------------------------------------------------------------------

  /// Skeleton mirroring the dashboard balance hero + stats row + recent items.
  ///
  /// Layout:
  /// - Large block (hero card with balance)
  /// - Row of 3 equal blocks (quick-action buttons)
  /// - 2 skeleton rows (recent activity items)
  factory SkeletonLoader.dashboardHero({int count = 1}) {
    return SkeletonLoader(
      itemCount: count,
      itemBuilder: (context, index) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBlock(
              width: double.infinity,
              height: 120,
              borderRadius: AppColors.radiusLarge,
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: SkeletonBlock(width: double.infinity, height: 56)),
                SizedBox(width: 12),
                Expanded(child: SkeletonBlock(width: double.infinity, height: 56)),
                SizedBox(width: 12),
                Expanded(child: SkeletonBlock(width: double.infinity, height: 56)),
              ],
            ),
            SizedBox(height: 16),
            SkeletonRow(),
            SizedBox(height: 12),
            SkeletonRow(),
          ],
        ),
      ),
    );
  }

  /// Skeleton mirroring an event card layout.
  ///
  /// Layout: icon circle + title bar + subtitle bar + trailing amount block.
  factory SkeletonLoader.eventCard({int count = 3}) {
    return SkeletonLoader(
      itemCount: count,
      itemBuilder: (context, index) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Row(
          children: [
            SkeletonCircle(size: 40),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBar(width: 120, height: 16),
                  SizedBox(height: 6),
                  SkeletonBar(width: 80, height: 12),
                ],
              ),
            ),
            SkeletonBlock(width: 48, height: 20),
          ],
        ),
      ),
    );
  }

  /// Skeleton mirroring a group/logistics list row with avatar and text bars.
  ///
  /// Replaces the previous opaque-rectangle groupList with content-aware primitives.
  factory SkeletonLoader.groupList({int count = 3}) {
    return SkeletonLoader(
      itemCount: count,
      itemBuilder: (context, index) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonRow(circleSize: 44, barWidth: 160, smallBarWidth: 100),
            SizedBox(height: 12),
            SkeletonBar(width: 200, height: 12),
          ],
        ),
      ),
    );
  }

  /// Skeleton mirroring an expense row layout.
  ///
  /// Layout: avatar circle + title + category row + trailing amount.
  factory SkeletonLoader.expenseList({int count = 5}) {
    return SkeletonLoader(
      itemCount: count,
      itemBuilder: (context, index) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: SkeletonRow(
                circleSize: 40,
                barWidth: 140,
                smallBarWidth: 80,
              ),
            ),
            SizedBox(width: 8),
            SkeletonBar(width: 60, height: 16),
          ],
        ),
      ),
    );
  }

  /// Skeleton mirroring a gear item row layout.
  ///
  /// Layout: checkbox block + item name bar + assignee bar.
  factory SkeletonLoader.gearList({int count = 5}) {
    return SkeletonLoader(
      itemCount: count,
      itemBuilder: (context, index) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Row(
          children: [
            SkeletonBlock(width: 24, height: 24, borderRadius: 4),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBar(width: 160, height: 14),
                  SizedBox(height: 6),
                  SkeletonBar(width: 100, height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Generic plain-card skeleton fallback for screens without a named variant.
  ///
  /// Produces [SkeletonCard] items of uniform height 72dp.
  factory SkeletonLoader.generic({int count = 5}) {
    return SkeletonLoader(
      itemCount: count,
      itemBuilder: (context, index) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 6),
        child: SkeletonCard(height: 72),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Backward-compatible factories (preserved for existing consumers)
  // ---------------------------------------------------------------------------

  /// Skeleton for gear/expense list items.
  ///
  /// Preserved for backward compatibility. Delegates to [generic].
  factory SkeletonLoader.cardList({int count = 5}) {
    return SkeletonLoader(
      itemCount: count,
      itemBuilder: (context, index) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 6),
        child: SkeletonCard(height: 72),
      ),
    );
  }

  /// Skeleton for document list items.
  ///
  /// Preserved for backward compatibility.
  factory SkeletonLoader.documentList({int count = 4}) {
    return SkeletonLoader(
      itemCount: count,
      itemBuilder: (context, index) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: SkeletonCard(height: 80),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surfaceLight, // #F3F4F6 — warm-neutral base
      highlightColor: AppColors.surface, // #F8F9FA — warm-neutral highlight
      child: SingleChildScrollView(
        // NeverScrollableScrollPhysics prevents user scroll while keeping
        // Column items clipped to bounded parent height (e.g. inside Expanded).
        // Column avoids zero-height that ListView.builder produces in
        // unbounded parents (e.g. inside a vertical Column without Expanded).
        physics: const NeverScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            children: List.generate(itemCount, (index) => itemBuilder(context, index)),
          ),
        ),
      ),
    );
  }
}
