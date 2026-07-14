import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../shared/widgets/skeleton_loader.dart';
import '../../../../shared/widgets/skeleton_primitives.dart';
import '../../keys/profile_keys.dart';

/// Layout-matched skeleton for the 3-tile stats grid (#488).
class StatsGridSkeleton extends StatelessWidget {
  const StatsGridSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      itemCount: 1,
      itemBuilder: (context, _) => Padding(
        key: ProfileKeys.statsSection,
        padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
        child: const Row(
          children: [
            Expanded(
              child: SkeletonBlock(
                width: double.infinity,
                height: 88,
                borderRadius: 16,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: SkeletonBlock(
                width: double.infinity,
                height: 88,
                borderRadius: 16,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: SkeletonBlock(
                width: double.infinity,
                height: 88,
                borderRadius: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
