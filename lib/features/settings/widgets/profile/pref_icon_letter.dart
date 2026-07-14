import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';

class PrefIconLetter extends StatelessWidget {
  const PrefIconLetter({super.key, required this.letter, required this.bg});
  final String letter;
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
      child: Text(
        letter,
        style: AppTypography.displayOf(
          context,
          fontSize: 15,
          color: context.colors.textPrimary,
          height: 1.0,
        ),
      ),
    );
  }
}
