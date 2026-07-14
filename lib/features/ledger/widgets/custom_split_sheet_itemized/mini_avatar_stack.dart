import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../shared/widgets/r_avatar.dart';
import '../custom_split_sheet.dart';

class MiniAvatarStack extends StatelessWidget {
  const MiniAvatarStack({super.key, required this.participants});

  final List<SplitParticipant> participants;

  @override
  Widget build(BuildContext context) {
    const max = 4;
    final shown = participants.take(max).toList();
    return SizedBox(
      height: 20,
      width: 20.0 + (shown.length - 1) * 13,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            PositionedDirectional(
              start: i * 13.0,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.colors.cardSurface,
                    width: 1.5,
                  ),
                ),
                // #1168: colorKey = participant.id (== member userId).
                child: RAvatar(
                  name: shown[i].name,
                  size: 18,
                  colorKey: shown[i].id,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
