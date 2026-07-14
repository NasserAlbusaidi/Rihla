import 'package:flutter/material.dart';

import '../../../../shared/widgets/skeleton_loader.dart';

class LoadingState extends StatelessWidget {
  const LoadingState({super.key});
  @override
  Widget build(BuildContext context) {
    return SafeArea(child: SkeletonLoader.generic(count: 3));
  }
}
