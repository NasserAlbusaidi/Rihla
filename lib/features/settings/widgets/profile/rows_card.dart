import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';

class RowsCard extends StatelessWidget {
  const RowsCard({required this.rows, super.key});
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(context.spacing.radiusCard),
        boxShadow: context.shadows.raised,
      ),
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space16),
      child: Column(children: rows),
    );
  }
}
