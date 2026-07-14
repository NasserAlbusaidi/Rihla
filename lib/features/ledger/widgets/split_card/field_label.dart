import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.caption(
        context,
        fontSize: 10.5,
        letterSpacing: 1.0,
        fontWeight: FontWeight.w700,
        color: context.colors.textSecondary,
      ),
    );
  }
}
