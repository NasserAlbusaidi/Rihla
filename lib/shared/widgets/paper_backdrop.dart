import 'package:flutter/material.dart';

import '../../core/theme/tokens/domain_aliases.dart';

/// Paper-wash gradient backdrop for a full-screen surface.
///
/// A [washHeight]-tall gradient fades from [AppColorTokens.paperDeep] into
/// the scaffold background at the top of the screen.
class PaperBackdrop extends StatelessWidget {
  const PaperBackdrop({super.key, required this.child, this.washHeight = 240});

  final Widget child;
  final double washHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(
      children: [
        PositionedDirectional(
          top: 0,
          start: 0,
          end: 0,
          height: washHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [colors.paperDeep, colors.scaffoldBackground],
              ),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}
