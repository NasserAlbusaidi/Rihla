import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/color_tokens.dart';

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
          'RECEIPT (OPTIONAL)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: AppColorTokens.light.textMuted,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: onPick,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColorTokens.light.inputFill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: receiptPath != null
                    ? AppColorTokens.light.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: receiptPath != null
                ? _ReceiptPreview(
                    receiptPath: receiptPath!,
                    onRemove: onRemove,
                  )
                : _ReceiptPlaceholder(),
          ),
        ),
        if (isUploading)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Uploading receipt...'),
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

  const _ReceiptPreview({
    required this.receiptPath,
    required this.onRemove,
  });

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
                'Receipt attached',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColorTokens.light.textPrimary,
                ),
              ),
              Text(
                'Tap to change',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColorTokens.light.textMuted,
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
              color: AppColorTokens.light.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Iconsax.trash,
              size: 18,
              color: AppColorTokens.light.error,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReceiptPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColorTokens.light.cardSurface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Iconsax.camera,
            size: 20,
            color: AppColorTokens.light.textMuted,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'Add a receipt photo',
          style: TextStyle(
            color: AppColorTokens.light.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
