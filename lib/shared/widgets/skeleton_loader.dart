import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'skeleton_primitives.dart';
import '../../core/theme/tokens/domain_aliases.dart';

/// Reusable skeleton loading placeholders.
///
/// Named factory variants produce content-aware skeletons that mirror real
/// widget layouts, preventing layout jump when data loads.
///
/// All variants wrap their children in [Shimmer.fromColors] using the active
/// theme's warm-neutral tokens: `baseColor` uses `context.colors.inputFill`
/// and `highlightColor` uses `context.colors.cardSurface`.
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
      itemBuilder: (context, index) => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space24,
          vertical: context.spacing.space8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBlock(
              width: double.infinity,
              height: 120,
              borderRadius: 16,
            ),
            SizedBox(height: context.spacing.space16),
            Row(
              children: [
                const Expanded(child: SkeletonBlock(width: double.infinity, height: 56)),
                SizedBox(width: context.spacing.space12),
                const Expanded(child: SkeletonBlock(width: double.infinity, height: 56)),
                SizedBox(width: context.spacing.space12),
                const Expanded(child: SkeletonBlock(width: double.infinity, height: 56)),
              ],
            ),
            SizedBox(height: context.spacing.space16),
            const SkeletonRow(),
            SizedBox(height: context.spacing.space12),
            const SkeletonRow(),
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
      itemBuilder: (context, index) => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space24,
          vertical: context.spacing.space8,
        ),
        child: Row(
          children: [
            const SkeletonCircle(size: 40),
            SizedBox(width: context.spacing.space12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBar(width: 120, height: 16),
                  SizedBox(height: 6),
                  SkeletonBar(width: 80, height: 12),
                ],
              ),
            ),
            const SkeletonBlock(width: 48, height: 20),
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
      itemBuilder: (context, index) => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space24,
          vertical: context.spacing.space8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonRow(circleSize: 44, barWidth: 160, smallBarWidth: 100),
            SizedBox(height: context.spacing.space12),
            const SkeletonBar(width: 200, height: 12),
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
      itemBuilder: (context, index) => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space24,
          vertical: context.spacing.space8,
        ),
        child: Row(
          children: [
            const Expanded(
              child: SkeletonRow(
                circleSize: 40,
                barWidth: 140,
                smallBarWidth: 80,
              ),
            ),
            SizedBox(width: context.spacing.space8),
            const SkeletonBar(width: 60, height: 16),
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
      itemBuilder: (context, index) => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space24,
          vertical: context.spacing.space8,
        ),
        child: Row(
          children: [
            const SkeletonBlock(width: 24, height: 24, borderRadius: 4),
            SizedBox(width: context.spacing.space12),
            const Expanded(
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

  /// Skeleton mirroring the Memories photo grid layout.
  ///
  /// Renders a 3-column grid of [count] equal skeleton blocks (default 9).
  /// Used as the loading placeholder for MemoriesScreen.
  factory SkeletonLoader.photoGrid({int count = 9}) {
    return SkeletonLoader(
      itemCount: 1,
      itemBuilder: (context, index) => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space16,
          vertical: context.spacing.space8,
        ),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: count,
          itemBuilder: (context2, index2) => const SkeletonBlock(
            width: double.infinity,
            height: double.infinity,
            borderRadius: 8,
          ),
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
      itemBuilder: (context, index) => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space24,
          vertical: 6,
        ),
        child: const SkeletonCard(height: 72),
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
      itemBuilder: (context, index) => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space24,
          vertical: 6,
        ),
        child: const SkeletonCard(height: 72),
      ),
    );
  }

  /// Skeleton for document list items.
  ///
  /// Preserved for backward compatibility.
  factory SkeletonLoader.documentList({int count = 4}) {
    return SkeletonLoader(
      itemCount: count,
      itemBuilder: (context, index) => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space20,
          vertical: 6,
        ),
        child: const SkeletonCard(height: 80),
      ),
    );
  }

  /// Skeleton for a single card loading state (widget-level loading).
  ///
  /// Returns a [Builder] so the shimmer colors resolve against the active
  /// theme via `context.colors` inside the nearest BuildContext.
  static Widget card() {
    return Builder(
      builder: (context) => Shimmer.fromColors(
        baseColor: context.colors.inputFill,
        highlightColor: context.colors.cardSurface,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.spacing.space24,
            vertical: context.spacing.space12,
          ),
          child: const SkeletonCard(height: 120),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: context.colors.inputFill, // warm-neutral base (theme-aware)
      highlightColor: context.colors.cardSurface, // warm-neutral highlight (theme-aware)
      child: SingleChildScrollView(
        // NeverScrollableScrollPhysics prevents user scroll while keeping
        // Column items clipped to bounded parent height (e.g. inside Expanded).
        // Column avoids zero-height that ListView.builder produces in
        // unbounded parents (e.g. inside a vertical Column without Expanded).
        physics: const NeverScrollableScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.only(top: context.spacing.space12),
          child: Column(
            children: List.generate(itemCount, (index) => itemBuilder(context, index)),
          ),
        ),
      ),
    );
  }
}
