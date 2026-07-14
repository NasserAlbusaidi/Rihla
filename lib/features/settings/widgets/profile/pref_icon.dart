import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';

class PrefIcon extends StatelessWidget {
  const PrefIcon({super.key, required this.icon, required this.bg});
  final IconData icon;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 16, color: context.colors.textPrimary),
    );
  }
}
