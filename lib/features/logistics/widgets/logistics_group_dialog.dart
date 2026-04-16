import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../keys/logistics_keys.dart';
import '../models/sub_group_model.dart';
import '../providers/sub_group_provider.dart';

/// Create / edit sub-group bottom sheet for the Logistics screen.
///
/// Owns its own [TextEditingController]s initialised from [initialGroup].
/// On submit, calls [onCreateGroup] or [onUpdateGroup] and pops itself.
class LogisticsGroupDialog extends StatefulWidget {
  /// Non-null when editing an existing group; null for create mode.
  final SubGroup? initialGroup;

  /// Called when creating a new group (initialGroup == null).
  final Future<void> Function(String name, int capacity) onCreateGroup;

  /// Called when saving edits to an existing group (initialGroup != null).
  final Future<void> Function(String name, int capacity) onUpdateGroup;

  const LogisticsGroupDialog({
    super.key,
    required this.initialGroup,
    required this.onCreateGroup,
    required this.onUpdateGroup,
  });

  @override
  State<LogisticsGroupDialog> createState() => _LogisticsGroupDialogState();
}

class _LogisticsGroupDialogState extends State<LogisticsGroupDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _capacityController;

  @override
  void initState() {
    super.initState();
    final group = widget.initialGroup;
    _nameController = TextEditingController(text: group?.name ?? '');
    _capacityController =
        TextEditingController(text: group != null ? group.capacity.toString() : '4');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.initialGroup;
    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColorTokens.light.cardSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            group != null ? 'EDIT GROUP' : 'NEW GROUP',
            key: group != null ? null : LogisticsKeys.createGroupTitle,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: AppColorTokens.light.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nameController,
            autofocus: true,
            inputFormatters: [LengthLimitingTextInputFormatter(50)],
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppColorTokens.light.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'CAR NAME (e.g. DEFENDER 1)',
              prefixIcon:
                  Icon(Iconsax.car, color: AppColorTokens.light.textMuted),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _capacityController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              LengthLimitingTextInputFormatter(2),
              FilteringTextInputFormatter.digitsOnly,
            ],
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppColorTokens.light.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'CAPACITY',
              prefixIcon:
                  Icon(Iconsax.people, color: AppColorTokens.light.textMuted),
            ),
          ),
          const SizedBox(height: 24),
          // Use Consumer to watch loading state without making the whole
          // widget a ConsumerWidget (keeps StatefulWidget ownership of controllers).
          Consumer(
            builder: (context, ref, _) {
              final isLoading = ref.watch(subGroupLoadingProvider);
              return SizedBox(
                height: 64,
                child: ElevatedButton(
                  key: group != null ? null : LogisticsKeys.createGroupButton,
                  onPressed: isLoading ? null : _onSubmit,
                  child: isLoading
                      ? const Text(
                          'SAVING...',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        )
                      : Text(
                          group != null ? 'SAVE CHANGES' : 'CREATE GROUP',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _onSubmit() {
    final name = _nameController.text.trim();
    final capacity = int.tryParse(_capacityController.text) ?? 4;

    if (name.isEmpty) return;

    HapticService.lightClick();
    Navigator.pop(context);

    if (widget.initialGroup != null) {
      widget.onUpdateGroup(name, capacity);
    } else {
      widget.onCreateGroup(name, capacity);
    }
  }
}
