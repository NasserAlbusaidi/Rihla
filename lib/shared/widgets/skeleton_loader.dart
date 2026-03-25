import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/theme/app_theme.dart';

/// Reusable skeleton loading placeholders
class SkeletonLoader extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  const SkeletonLoader({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  /// Skeleton for gear/expense list items
  factory SkeletonLoader.cardList({int count = 5}) {
    return SkeletonLoader(
      itemCount: count,
      itemBuilder: (context, index) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 6),
        child: _SkeletonCard(height: 72),
      ),
    );
  }

  /// Skeleton for document list items
  factory SkeletonLoader.documentList({int count = 4}) {
    return SkeletonLoader(
      itemCount: count,
      itemBuilder: (context, index) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: _SkeletonCard(height: 80),
      ),
    );
  }

  /// Skeleton for logistics groups
  factory SkeletonLoader.groupList({int count = 3}) {
    return SkeletonLoader(
      itemCount: count,
      itemBuilder: (context, index) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: _SkeletonCard(height: 120),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surfaceLight,
      highlightColor: AppColors.surface,
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 12),
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final double height;

  const _SkeletonCard({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}
