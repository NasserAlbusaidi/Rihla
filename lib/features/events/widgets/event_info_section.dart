import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/utils/localized_dates.dart';
import '../../../core/utils/write_ack.dart';
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
  const EventInfoSection({super.key, required this.event});

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
    _descriptionController = TextEditingController(
      text: widget.event.description ?? '',
    );
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

  String _formatDate(DateTime? date) {
    if (date == null) return context.l10n.eventNotSet;
    return formatShortMonthDayYear(context, date);
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
          SnackBar(
            content: Text(context.l10n.eventNameEmpty),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() => _isSaving = true);
    try {
      final description = _descriptionController.text.trim();
      final connectivity = ref.read(connectivityProvider.notifier);
      final connectivityStatus = ref.read(connectivityProvider);
      final outcome = await awaitServerAck(
        ref
            .read(eventServiceProvider)
            .updateEvent(
              groupId: widget.event.groupId,
              eventId: widget.event.id,
              name: name != widget.event.name ? name : null,
              startDate: _startDate,
              endDate: _endDate,
              description: description.isNotEmpty ? description : null,
            ),
        skipWait: connectivityStatus != ConnectivityStatus.online,
      );
      if (outcome == WriteAck.acked) {
        connectivity.noteLocalWrite();
      } else {
        connectivity.noteQueuedWrite();
      }
      if (mounted) {
        HapticService.success();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.eventUpdated,
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: context.colors.textPrimary,
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
          SnackBar(
            content: Text(context.l10n.eventSaveFailed),
            duration: const Duration(seconds: 3),
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
        SizedBox(height: context.spacing.space8),
        Container(
          key: EventKeys.infoSection,
          decoration: BoxDecoration(
            color: context.colors.cardSurface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: context.shadows.raised,
          ),
          padding: EdgeInsets.all(context.spacing.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildNameField(),
              SizedBox(height: context.spacing.space12),
              _buildDateRow(),
              SizedBox(height: context.spacing.space12),
              _buildDescriptionField(),
              SizedBox(height: context.spacing.space16),
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
        Icon(Iconsax.setting_2, size: 16, color: context.colors.textSecondary),
        const SizedBox(width: 6),
        Text(
          context.l10n.eventDetailsSection,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.colors.textSecondary,
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
      prefixIcon: Icon(icon, size: 18, color: context.colors.textSecondary),
      filled: true,
      fillColor: context.colors.inputFillWarm,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: context.colors.borderWarm),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: context.colors.focusBorderWarm,
          width: 1.5,
        ),
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: context.spacing.space12,
        vertical: context.spacing.space12,
      ),
    );
  }

  Widget _buildNameField() {
    return TextField(
      controller: _nameController,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: context.colors.textPrimary,
      ),
      decoration: _fieldDecoration(
        labelText: context.l10n.eventNameLabel,
        icon: Iconsax.text,
      ),
    );
  }

  Widget _buildDateRow() {
    return Row(
      children: [
        Expanded(child: _buildDateTile(isStart: true)),
        SizedBox(width: context.spacing.space8),
        Expanded(child: _buildDateTile(isStart: false)),
      ],
    );
  }

  Widget _buildDateTile({required bool isStart}) {
    final date = isStart ? _startDate : _endDate;
    final label = isStart
        ? context.l10n.eventStartDate
        : context.l10n.eventEndDate;

    return GestureDetector(
      onTap: () {
        HapticService.selection();
        _pickDate(isStart: isStart);
      },
      child: AbsorbPointer(
        // #625: a read-only date display, not an input. A TextField here forced
        // an inline TextEditingController allocated on every build and never
        // disposed (the State disposes only name/description). InputDecorator +
        // Text renders the identical decoration with nothing to leak.
        child: InputDecorator(
          decoration: _fieldDecoration(
            labelText: label,
            icon: Iconsax.calendar,
          ),
          child: Text(
            _formatDate(date),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: date == null
                  ? context.colors.textSecondary
                  : context.colors.textPrimary,
            ),
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
        color: context.colors.textPrimary,
      ),
      decoration:
          _fieldDecoration(
            labelText: context.l10n.eventDescriptionLabel,
            icon: Iconsax.note,
          ).copyWith(
            alignLabelWithHint: true,
            contentPadding: EdgeInsets.symmetric(
              horizontal: context.spacing.space12,
              vertical: 14,
            ),
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
          backgroundColor: context.colors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _isSaving
            ? SizedBox(
                width: context.spacing.space20,
                height: context.spacing.space20,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                context.l10n.eventSaveChanges,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}
