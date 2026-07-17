import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../shared/widgets/skeleton_loader.dart';

class LoadingState extends StatelessWidget {
  const LoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final statusBar = MediaQuery.of(context).padding.top;
    return Column(
      children: [
        SizedBox(
          height: 168 + statusBar,
          child: Container(color: colors.cardSoft),
        ),
        Expanded(child: SkeletonLoader.groupList()),
      ],
    );
  }
}
