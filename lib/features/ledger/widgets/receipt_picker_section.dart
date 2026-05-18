import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

/// Receipt image picker and preview for expense entry.
class ReceiptPickerSection extends StatelessWidget {
  final String? receiptPath;
  final bool isUploading;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const ReceiptPickerSection({
    super.key,
    required this.receiptPath,
    required this.isUploading,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.editorReceiptOptional,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: context.colors.textSecondary,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: onPick,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.colors.inputFill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: receiptPath != null
                    ? context.colors.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: receiptPath != null
                ? _ReceiptPreview(receiptPath: receiptPath!, onRemove: onRemove)
                : const _ReceiptPlaceholder(),
          ),
        ),
        if (isUploading)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(context.l10n.editorReceiptUploading),
              ],
            ),
          ),
      ],
    );
  }
}

class _ReceiptPreview extends StatelessWidget {
  final String receiptPath;
  final VoidCallback onRemove;

  const _ReceiptPreview({required this.receiptPath, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(receiptPath),
            width: 60,
            height: 60,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.editorReceiptAttached,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                ),
              ),
              Text(
                context.l10n.editorReceiptTapToChange,
                style: TextStyle(
                  fontSize: 12,
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () {
            HapticService.lightClick();
            onRemove();
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.colors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Iconsax.trash, size: 18, color: context.colors.error),
          ),
        ),
      ],
    );
  }
}

class _ReceiptPlaceholder extends StatelessWidget {
  const _ReceiptPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.colors.cardSurface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Iconsax.camera,
            size: 20,
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          context.l10n.editorReceiptAddPhoto,
          style: TextStyle(
            color: context.colors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
