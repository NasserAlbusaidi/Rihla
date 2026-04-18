import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

/// Input row for adding a new gear item.
///
/// The [controller] is owned by the parent screen so that [FocusNode]-based
/// auto-scrolling (via [_focusAddField]) can work without coupling.
/// [isHighPriority] and [onPriorityChanged] are lifted state so the screen
/// can reset priority after a successful add.
class GearAddInput extends StatelessWidget {
  final TextEditingController controller;
  final bool isHighPriority;
  final ValueChanged<bool> onPriorityChanged;
  final VoidCallback onSubmit;
  final FocusNode? focusNode;

  const GearAddInput({
    super.key,
    required this.controller,
    required this.isHighPriority,
    required this.onPriorityChanged,
    required this.onSubmit,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.colors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.inputFill),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Iconsax.flash,
              color: isHighPriority
                  ? context.colors.errorText
                  // textMuted-decorative-justified: inactive priority flash affordance
                  : context.colors.textMuted,
              size: 20,
            ),
            onPressed: () {
              HapticService.lightClick();
              onPriorityChanged(!isHighPriority);
            },
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              inputFormatters: [LengthLimitingTextInputFormatter(100)],
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'ADD GEAR ITEM...',
                hintStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: context.colors.textSecondary,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onSubmitted: (_) => onSubmit(),
            ),
          ),
          IconButton(
            icon: Icon(
              Iconsax.add_circle,
              color: context.colors.primary,
              size: 28,
            ),
            onPressed: () {
              HapticService.lightClick();
              onSubmit();
            },
          ),
        ],
      ),
    );
  }
}
