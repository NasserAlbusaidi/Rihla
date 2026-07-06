import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';

class EditorSection extends StatelessWidget {
  const EditorSection({
    super.key,
    required this.title,
    required this.child,
    this.showRequiredMarker = false,
  });

  final String title;
  final Widget child;

  /// #807: renders a trailing asterisk so a mandatory field announces itself
  /// before a blocked submit does. Opt-in — only the add-mode Category
  /// section passes true (mirrors the `!_isEdit` validation gate).
  final bool showRequiredMarker;

  @override
  Widget build(BuildContext context) {
    final titleStyle = AppTypography.sans(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      color: context.colors.textPrimary,
    );
    return Padding(
      padding: EdgeInsets.only(top: context.spacing.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.spacing.space24),
            child: showRequiredMarker
                ? Text.rich(
                    TextSpan(
                      text: title,
                      style: titleStyle,
                      children: [
                        TextSpan(
                          text: ' *',
                          style: AppTypography.sans(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: context.colors.error,
                          ),
                        ),
                      ],
                    ),
                  )
                : Text(title, style: titleStyle),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
