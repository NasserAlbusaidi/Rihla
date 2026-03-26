import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/error_widgets.dart';
import '../../../core/services/haptic_service.dart';
import '../../trip/models/trip_model.dart';
import '../../trip/providers/trip_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/expense_model.dart';

/// Scope selector (global/subgroup/custom/personal) with custom participant
/// picker and payer selector for leaders.
class SplitScopeSelector extends ConsumerWidget {
  final String tripId;
  final ExpenseScope scope;
  final ValueChanged<ExpenseScope> onScopeChanged;
  final Set<String> customSplitParticipants;
  final ValueChanged<Set<String>> onCustomSplitChanged;
  final String? selectedSubGroupId;
  final VoidCallback onAutoSelectSubGroup;
  final ValueChanged<String?> onSubGroupIdCleared;
  final String? selectedPayerId;
  final ValueChanged<String?> onPayerChanged;

  const SplitScopeSelector({
    super.key,
    required this.tripId,
    required this.scope,
    required this.onScopeChanged,
    required this.customSplitParticipants,
    required this.onCustomSplitChanged,
    required this.selectedSubGroupId,
    required this.onAutoSelectSubGroup,
    required this.onSubGroupIdCleared,
    required this.selectedPayerId,
    required this.onPayerChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Scope Tabs
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _ScopeTab(
                    label: 'Global',
                    scope: ExpenseScope.global,
                    icon: Iconsax.global,
                    isSelected: scope == ExpenseScope.global,
                    onTap: () => _handleScopeChange(ExpenseScope.global),
                  ),
                  _ScopeTab(
                    label: 'My Car',
                    scope: ExpenseScope.subGroup,
                    icon: Iconsax.car,
                    isSelected: scope == ExpenseScope.subGroup,
                    onTap: () => _handleScopeChange(ExpenseScope.subGroup),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _ScopeTab(
                    label: 'Custom',
                    scope: ExpenseScope.custom,
                    icon: Iconsax.people,
                    isSelected: scope == ExpenseScope.custom,
                    onTap: () => _handleScopeChange(ExpenseScope.custom),
                  ),
                  _ScopeTab(
                    label: 'Personal',
                    scope: ExpenseScope.personal,
                    icon: Iconsax.user,
                    isSelected: scope == ExpenseScope.personal,
                    onTap: () => _handleScopeChange(ExpenseScope.personal),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Custom participant selection
        if (scope == ExpenseScope.custom) ...[
          const SizedBox(height: 16),
          _CustomParticipantSelector(
            tripId: tripId,
            customSplitParticipants: customSplitParticipants,
            onCustomSplitChanged: onCustomSplitChanged,
          ),
        ],
        const SizedBox(height: 24),
        // Paid By selector (for leaders only)
        _PayerSelector(
          tripId: tripId,
          selectedPayerId: selectedPayerId,
          onPayerChanged: onPayerChanged,
        ),
      ],
    );
  }

  void _handleScopeChange(ExpenseScope newScope) {
    HapticService.selection();
    onScopeChanged(newScope);

    if (newScope == ExpenseScope.subGroup) {
      onAutoSelectSubGroup();
    } else {
      onSubGroupIdCleared(null);
    }
  }
}

class _ScopeTab extends StatelessWidget {
  final String label;
  final ExpenseScope scope;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ScopeTab({
    required this.label,
    required this.scope,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected ? AppColors.cardShadow : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? AppColors.mint : AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? AppColors.textPrimary
                      : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Multi-select participant list for custom splits.
class _CustomParticipantSelector extends ConsumerWidget {
  final String tripId;
  final Set<String> customSplitParticipants;
  final ValueChanged<Set<String>> onCustomSplitChanged;

  const _CustomParticipantSelector({
    required this.tripId,
    required this.customSplitParticipants,
    required this.onCustomSplitChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final participantsAsync = ref.watch(
      tripLogisticsParticipantsProvider(tripId),
    );
    final currentParticipant = ref.watch(
      currentParticipantProvider(tripId),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'SELECT PARTICIPANTS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: AppColors.textMuted,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              '${customSplitParticipants.length} selected',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: customSplitParticipants.isNotEmpty
                    ? AppColors.mint
                    : AppColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(16),
          ),
          constraints: const BoxConstraints(maxHeight: 200),
          child: participantsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                const InlineErrorWidget(message: 'Unable to load participants'),
            data: (participants) {
              // Exclude current user from selection (they're auto-included)
              final otherParticipants = participants
                  .where((p) => p.id != currentParticipant?.id)
                  .toList();

              if (otherParticipants.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No other participants to select'),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                itemCount: otherParticipants.length,
                itemBuilder: (context, index) {
                  final participant = otherParticipants[index];
                  final isSelected = customSplitParticipants.contains(
                    participant.id,
                  );

                  return _ParticipantTile(
                    participant: participant,
                    isSelected: isSelected,
                    onToggle: () {
                      HapticService.lightClick();
                      final updated = Set<String>.from(customSplitParticipants);
                      if (isSelected) {
                        updated.remove(participant.id);
                      } else {
                        updated.add(participant.id);
                      }
                      onCustomSplitChanged(updated);
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  final Participant participant;
  final bool isSelected;
  final VoidCallback onToggle;

  const _ParticipantTile({
    required this.participant,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.mint.withValues(alpha: 0.2)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            (participant.displayName ?? 'U')[0].toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isSelected ? AppColors.mint : AppColors.textMuted,
            ),
          ),
        ),
      ),
      title: Text(
        participant.displayName ?? 'Unknown',
        style: TextStyle(
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: participant.isShadow
          ? const Text(
              'Shadow Profile',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            )
          : null,
      trailing: Checkbox(
        value: isSelected,
        activeColor: AppColors.mint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        onChanged: (_) => onToggle(),
      ),
      onTap: onToggle,
    );
  }
}

/// Dropdown to select who paid, visible only to leaders.
class _PayerSelector extends ConsumerWidget {
  final String tripId;
  final String? selectedPayerId;
  final ValueChanged<String?> onPayerChanged;

  const _PayerSelector({
    required this.tripId,
    required this.selectedPayerId,
    required this.onPayerChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentParticipant = ref.watch(
      currentParticipantProvider(tripId),
    );
    final trip = ref
        .watch(userTripsProvider)
        .valueOrNull
        ?.cast<Trip?>()
        .firstWhere(
          (t) => t!.id == tripId,
          orElse: () => null,
        );
    final participantsAsync = ref.watch(
      tripLogisticsParticipantsProvider(tripId),
    );
    final participants = participantsAsync.valueOrNull ?? [];

    // Check if current user is the leader
    final isLeader = trip?.leaderId == ref.watch(currentUserProvider)?.id;

    // If not leader or no participants, don't show
    if (!isLeader || participants.isEmpty) {
      return const SizedBox.shrink();
    }

    // Default to current participant if not set
    final effectivePayerId = selectedPayerId ?? currentParticipant?.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PAID BY',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: AppColors.textMuted,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.textMuted.withValues(alpha: 0.3),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: effectivePayerId,
              isExpanded: true,
              icon: const Icon(Iconsax.arrow_down_1),
              items: participants.map((p) {
                final isMe = p.id == currentParticipant?.id;
                return DropdownMenuItem(
                  value: p.id,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.primaryLight,
                        child: Text(
                          (p.displayName ?? 'U')[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isMe
                              ? '${p.displayName ?? 'Unknown'} (Me)'
                              : p.displayName ?? 'Unknown',
                          style: TextStyle(
                            fontWeight: isMe
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                HapticService.lightClick();
                onPayerChanged(value);
              },
            ),
          ),
        ),
      ],
    );
  }
}
