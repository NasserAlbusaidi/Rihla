import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../models/trip_model.dart';
import '../providers/trip_provider.dart';

/// Edit Trip Screen - Allows editing trip name, dates, and icon
class EditTripScreen extends ConsumerStatefulWidget {
  final Trip trip;

  const EditTripScreen({super.key, required this.trip});

  @override
  ConsumerState<EditTripScreen> createState() => _EditTripScreenState();
}

class _EditTripScreenState extends ConsumerState<EditTripScreen> {
  late TextEditingController _nameController;
  late DateTime? _startDate;
  late DateTime? _endDate;
  late String _selectedIcon;
  bool _isLoading = false;

  static const List<Map<String, dynamic>> _tripIcons = [
    {'name': 'airplane', 'icon': Iconsax.airplane},
    {'name': 'car', 'icon': Iconsax.car},
    {'name': 'camping', 'icon': Iconsax.home_2},
    {'name': 'hiking', 'icon': Iconsax.routing_2},
    {'name': 'beach', 'icon': Iconsax.sun_1},
    {'name': 'mountain', 'icon': Iconsax.cloud},
    {'name': 'ship', 'icon': Iconsax.ship},
    {'name': 'train', 'icon': Iconsax.bus},
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.trip.name);
    _startDate = widget.trip.startDate;
    _endDate = widget.trip.endDate;
    _selectedIcon = widget.trip.icon;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  IconData _getIconData(String iconName) {
    return _tripIcons.firstWhere(
          (i) => i['name'] == iconName,
          orElse: () => _tripIcons.first,
        )['icon']
        as IconData;
  }

  Future<void> _saveTrip() async {
    if (_nameController.text.trim().isEmpty) return;

    setState(() => _isLoading = true);

    final success = await ref
        .read(tripServiceProvider)
        .updateTrip(
          widget.trip.id,
          name: _nameController.text.trim(),
          startDate: _startDate,
          endDate: _endDate,
          icon: _selectedIcon,
        );

    setState(() => _isLoading = false);

    if (success && mounted) {
      ref.invalidate(userTripsProvider);
      ref.read(currentTripProvider.notifier).state = widget.trip.copyWith(
        name: _nameController.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
        icon: _selectedIcon,
      );
      Navigator.pop(context);
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart
          ? (_startDate ?? DateTime.now())
          : (_endDate ?? _startDate ?? DateTime.now()),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate != null && _endDate!.isBefore(picked)) {
            _endDate = null;
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader().animate().fadeIn().slideY(begin: -0.2),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Trip Name
                    _buildNameSection()
                        .animate()
                        .fadeIn(delay: 100.ms)
                        .slideY(begin: 0.1),

                    const SizedBox(height: 24),

                    // Trip Icon
                    _buildIconSection()
                        .animate()
                        .fadeIn(delay: 200.ms)
                        .slideY(begin: 0.1),

                    const SizedBox(height: 24),

                    // Dates
                    _buildDateSection()
                        .animate()
                        .fadeIn(delay: 300.ms)
                        .slideY(begin: 0.1),

                    const SizedBox(height: 32),

                    // Save Button
                    _buildSaveButton().animate().fadeIn(delay: 400.ms),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Iconsax.arrow_left),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Text(
              'Edit Trip',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildNameSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Iconsax.text, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text(
                'Trip Name',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(
              hintText: 'Enter trip name',
              filled: true,
              fillColor: AppColors.surfaceLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Iconsax.emoji_happy, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text(
                'Trip Icon',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _tripIcons.map((iconData) {
              final isSelected = _selectedIcon == iconData['name'];
              return GestureDetector(
                onTap: () =>
                    setState(() => _selectedIcon = iconData['name'] as String),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: isSelected ? AppColors.primaryGradient : null,
                    color: isSelected ? null : AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(16),
                    border: isSelected
                        ? null
                        : Border.all(color: AppColors.border),
                  ),
                  child: Icon(
                    iconData['icon'] as IconData,
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                    size: 28,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Iconsax.calendar_1, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text(
                'Trip Dates',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildDatePicker(
                  label: 'Start Date',
                  date: _startDate,
                  onTap: () => _pickDate(isStart: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDatePicker(
                  label: 'End Date',
                  date: _endDate,
                  onTap: () => _pickDate(isStart: false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: date != null
              ? Border.all(color: AppColors.primary, width: 1.5)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              date != null ? DateFormat('MMM d, yyyy').format(date) : 'Select',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: date != null
                    ? AppColors.textPrimary
                    : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _saveTrip,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Iconsax.tick_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Save Changes',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
