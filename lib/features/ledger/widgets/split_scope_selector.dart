import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/error_widgets.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/utils/expense_scope_display_name.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../auth/providers/auth_provider.dart';
import '../../events/models/event_model.dart';
import '../../trip/models/trip_model.dart';
import '../keys/ledger_keys.dart';
import '../models/expense_model.dart';

/// Derive participants directly from event data (logistics provider removed in Phase 39).
List<Participant> _eventParticipants(Event event) {
  return event.participantIds.map((id) {
    return Participant(
      id: id,
      tripId: event.id,
      role: ParticipantRole.member,
      joinedAt: event.createdAt,
      displayName: event.participantNames[id],
    );
  }).toList();
}

/// Scope selector (global/custom/personal) with custom participant picker and
/// payer selector for leaders. The Phase 39 strip removed the subGroup tab
/// alongside the logistics feature.
class SplitScopeSelector extends ConsumerWidget {
  final Event event;
  final ExpenseScope scope;
  final ValueChanged<ExpenseScope> onScopeChanged;
  final Set<String> customSplitParticipants;
  final ValueChanged<Set<String>> onCustomSplitChanged;
  final String? selectedPayerId;
  final ValueChanged<String?> onPayerChanged;

  const SplitScopeSelector({
    super.key,
    required this.event,
    required this.scope,
    required this.onScopeChanged,
    required this.customSplitParticipants,
    required this.onCustomSplitChanged,
    required this.selectedPayerId,
    required this.onPayerChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: context.colors.inputFill,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              _ScopeTab(
                label: expenseScopeDisplayName(
                  ExpenseScope.global,
                  context.l10n,
                ),
                icon: Iconsax.global,
                isSelected: scope == ExpenseScope.global,
                onTap: () => _handleScopeChange(ExpenseScope.global),
              ),
              _ScopeTab(
                label: expenseScopeDisplayName(
                  ExpenseScope.custom,
                  context.l10n,
                ),
                icon: Iconsax.people,
                isSelected: scope == ExpenseScope.custom,
                onTap: () => _handleScopeChange(ExpenseScope.custom),
              ),
              _ScopeTab(
                label: expenseScopeDisplayName(
                  ExpenseScope.personal,
                  context.l10n,
                ),
                icon: Iconsax.user,
                isSelected: scope == ExpenseScope.personal,
                onTap: () => _handleScopeChange(ExpenseScope.personal),
              ),
            ],
          ),
        ),
        if (scope == ExpenseScope.custom) ...[
          const SizedBox(height: 16),
          _CustomParticipantSelector(
            event: event,
            customSplitParticipants: customSplitParticipants,
            onCustomSplitChanged: onCustomSplitChanged,
          ),
        ],
        const SizedBox(height: 24),
        _PayerSelector(
          event: event,
          selectedPayerId: selectedPayerId,
          onPayerChanged: onPayerChanged,
        ),
      ],
    );
  }

  void _handleScopeChange(ExpenseScope newScope) {
    HapticService.selection();
    onScopeChanged(newScope);
  }
}

class _ScopeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ScopeTab({
    required this.label,
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
            color: isSelected ? context.colors.cardSurface : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected ? context.shadows.raised : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? context.colors.primary
                    : context.colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? context.colors.textPrimary
                      : context.colors.textSecondary,
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
  final Event event;
  final Set<String> customSplitParticipants;
  final ValueChanged<Set<String>> onCustomSplitChanged;

  const _CustomParticipantSelector({
    required this.event,
    required this.customSplitParticipants,
    required this.onCustomSplitChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final participants = _eventParticipants(event);
    final participantsAsync = AsyncValue.data(participants);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              context.l10n.editorSelectParticipants,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: context.colors.textSecondary,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              context.l10n.editorSelectedCount(customSplitParticipants.length),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: customSplitParticipants.isNotEmpty
                    ? context.colors.primary
                    : context.colors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: context.colors.inputFill,
            borderRadius: BorderRadius.circular(16),
          ),
          constraints: const BoxConstraints(maxHeight: 200),
          child: participantsAsync.when(
            loading: SkeletonLoader.card,
            error: (e, _) => InlineErrorWidget(
              message: context.l10n.editorUnableToLoadParticipants,
            ),
            data: (participants) {
              // #247: list ALL participants including the current user, so a
              // custom split can include yourself ("I paid, split me + him").
              if (participants.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(context.l10n.editorNoOtherParticipants),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                itemCount: participants.length,
                itemBuilder: (context, index) {
                  final participant = participants[index];
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
              ? context.colors.primary.withValues(alpha: 0.2)
              : context.colors.cardSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            (participant.displayName ??
                    context.l10n.editorUnknownParticipant)[0]
                .toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isSelected
                  ? context.colors.primary
                  : context.colors.textSecondary,
            ),
          ),
        ),
      ),
      title: Text(
        participant.displayName ?? context.l10n.editorUnknownParticipant,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: context.colors.textPrimary,
        ),
      ),
      subtitle: participant.isShadow
          ? Text(
              context.l10n.editorShadowProfile,
              style: TextStyle(
                fontSize: 11,
                color: context.colors.textSecondary,
              ),
            )
          : null,
      trailing: Checkbox(
        value: isSelected,
        activeColor: context.colors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        onChanged: (_) => onToggle(),
      ),
      onTap: onToggle,
    );
  }
}

/// Dropdown to select who paid, visible only to leaders.
class _PayerSelector extends ConsumerWidget {
  final Event event;
  final String? selectedPayerId;
  final ValueChanged<String?> onPayerChanged;

  const _PayerSelector({
    required this.event,
    required this.selectedPayerId,
    required this.onPayerChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final participants = _eventParticipants(event);

    final currentUid = ref.watch(currentUserProvider)?.uid;

    // #247: attribution is not leader-gated — any participant may record who
    // paid (firestore.rules only requires payerParticipantId ∈ participants).
    if (participants.isEmpty) {
      return const SizedBox.shrink();
    }

    final effectivePayerId = selectedPayerId ?? currentUid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          key: LedgerKeys.payerSectionLabel,
          context.l10n.editorPaidByLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: context.colors.textSecondary,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: context.colors.inputFill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: context.colors.textSecondary.withValues(alpha: 0.3),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: effectivePayerId,
              isExpanded: true,
              icon: const Icon(Iconsax.arrow_down_1),
              items: participants.map((p) {
                final isMe = p.id == currentUid;
                return DropdownMenuItem(
                  value: p.id,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: context.colors.selectionFill,
                        child: Text(
                          (p.displayName?.isNotEmpty == true
                                  ? p.displayName![0]
                                  : context.l10n.editorUnknownParticipant[0])
                              .toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: context.colors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isMe
                              ? context.l10n.editorParticipantMe(
                                  p.displayName ??
                                      context.l10n.editorUnknownParticipant,
                                )
                              : p.displayName ??
                                    context.l10n.editorUnknownParticipant,
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
