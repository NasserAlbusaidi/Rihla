import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';
import '../keys/event_keys.dart';
import '../models/event_model.dart';
import '../providers/event_provider.dart';

/// Editable event details section for EventSettingsScreen.
///
/// Mirrors GroupInfoSection pattern but with event-specific fields:
/// name, start date, end date, description, and save button.
///
/// Fire-and-forget pattern for async ops per Phase 26 P01 decision:
/// onPressed / onTap are synchronous; async work is internal.
class EventInfoSection extends ConsumerStatefulWidget {
  const EventInfoSection({
    super.key,
    required this.event,
  });

  final Event event;

  @override
  ConsumerState<EventInfoSection> createState() => _EventInfoSectionState();
}

class _EventInfoSectionState extends ConsumerState<EventInfoSection> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.event.name);
    _descriptionController =
        TextEditingController(text: widget.event.description ?? '');
    _startDate = widget.event.startDate;
    _endDate = widget.event.endDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  static String _formatDate(DateTime? date) {
    if (date == null) return 'Not set';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  /// Fire-and-forget date picker (synchronous onTap, async via .then()).
  void _pickDate({required bool isStart}) {
    showDatePicker(
      context: context,
      initialDate: (isStart ? _startDate : _endDate) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    ).then((picked) {
      if (picked != null && mounted) {
        setState(() {
          if (isStart) {
            _startDate = picked.toUtc();
          } else {
            _endDate = picked.toUtc();
          }
        });
      }
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Event name can't be empty."),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() => _isSaving = true);
    try {
      final description = _descriptionController.text.trim();
      await ref.read(eventServiceProvider).updateEvent(
            groupId: widget.event.groupId,
            eventId: widget.event.id,
            name: name != widget.event.name ? name : null,
            startDate: _startDate,
            endDate: _endDate,
            description: description.isNotEmpty ? description : null,
          );
      if (mounted) {
        HapticService.success();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Event updated',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColorTokens.light.textPrimary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't save changes. Try again."),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(),
        const SizedBox(height: 8),
        Container(
          key: EventKeys.infoSection,
          decoration: BoxDecoration(
            color: AppColorTokens.light.cardSurface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppShadowTokens.standard.raised,
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildNameField(),
              const SizedBox(height: 12),
              _buildDateRow(),
              const SizedBox(height: 12),
              _buildDescriptionField(),
              const SizedBox(height: 16),
              _buildSaveButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader() {
    return Row(
      children: [
        Icon(
          Iconsax.setting_2,
          size: 16,
          color: AppColorTokens.light.textSecondary,
        ),
        const SizedBox(width: 6),
        Text(
          'EVENT DETAILS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColorTokens.light.textSecondary,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration({
    required String labelText,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: labelText,
      prefixIcon: Icon(
        icon,
        size: 18,
        color: AppColorTokens.light.textSecondary,
      ),
      filled: true,
      fillColor: AppColorTokens.light.inputFillWarm,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColorTokens.light.borderWarm),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: AppColorTokens.light.focusBorderWarm,
          width: 1.5,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _buildNameField() {
    return TextField(
      controller: _nameController,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColorTokens.light.textPrimary,
      ),
      decoration: _fieldDecoration(
        labelText: 'Event Name',
        icon: Iconsax.text,
      ),
    );
  }

  Widget _buildDateRow() {
    return Row(
      children: [
        Expanded(child: _buildDateTile(isStart: true)),
        const SizedBox(width: 8),
        Expanded(child: _buildDateTile(isStart: false)),
      ],
    );
  }

  Widget _buildDateTile({required bool isStart}) {
    final date = isStart ? _startDate : _endDate;
    final label = isStart ? 'Start Date' : 'End Date';

    return GestureDetector(
      onTap: () {
        HapticService.selection();
        _pickDate(isStart: isStart);
      },
      child: AbsorbPointer(
        child: TextField(
          controller: TextEditingController(text: _formatDate(date)),
          readOnly: true,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: date == null
                ? AppColorTokens.light.textSecondary
                : AppColorTokens.light.textPrimary,
          ),
          decoration: _fieldDecoration(
            labelText: label,
            icon: Iconsax.calendar,
          ),
        ),
      ),
    );
  }

  Widget _buildDescriptionField() {
    return TextField(
      controller: _descriptionController,
      maxLines: 4,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColorTokens.light.textPrimary,
      ),
      decoration: _fieldDecoration(
        labelText: 'Description',
        icon: Iconsax.note,
      ).copyWith(
        alignLabelWithHint: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      key: EventKeys.saveChangesButton,
      height: 52,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSaving
            ? null
            : () {
                HapticService.lightClick();
                _save();
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColorTokens.light.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'Save Changes',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}
