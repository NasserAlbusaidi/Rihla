import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/error_widgets.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/utils/expense_scope_display_name.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../auth/providers/auth_provider.dart';
import '../../events/models/event_model.dart';
import '../../groups/providers/group_provider.dart';
import '../../groups/services/member_name_resolver.dart';
import '../../trip/models/trip_model.dart';
import '../keys/ledger_keys.dart';
import '../models/expense_model.dart';

/// Derive participants directly from event data (logistics provider removed in
/// Phase 39). [shadowUserIds] marks placeholder ("shadow") members — added by
/// name but not yet joined (#278) — so the picker can label them. The flag
/// lives on `GroupMember.isShadow`; rows are keyed by event-participant id,
/// which equals the member `userId`, so the lookup matches on that.
List<Participant> _eventParticipants(
  Event event, {
  Set<String> shadowUserIds = const {},
}) {
  return event.participantIds.map((id) {
    return Participant(
      id: id,
      tripId: event.id,
      role: ParticipantRole.member,
      joinedAt: event.createdAt,
      displayName: event.participantNames[id],
      isShadow: shadowUserIds.contains(id),
    );
  }).toList();
}

/// Shadow `userId`s for [groupId] from the live member roster. Empty while the
/// roster is loading or unavailable (e.g. no Firebase app in tests) — shadow
/// labelling is purely additive, so an empty set just renders no markers.
Set<String> _shadowUserIds(WidgetRef ref, String groupId) {
  final members = ref.watch(groupMembersProvider(groupId)).valueOrNull ?? const [];
  return {
    for (final m in members)
      if (m.isShadow) m.userId,
  };
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
          padding: EdgeInsets.all(context.spacing.space4),
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
          SizedBox(height: context.spacing.space16),
          _CustomParticipantSelector(
            event: event,
            customSplitParticipants: customSplitParticipants,
            onCustomSplitChanged: onCustomSplitChanged,
          ),
        ],
        SizedBox(height: context.spacing.space24),
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
          padding: EdgeInsets.symmetric(vertical: context.spacing.space12),
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
              SizedBox(width: context.spacing.space8),
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
    // #278: mark placeholder ("shadow") members not yet joined.
    final participants = _eventParticipants(
      event,
      shadowUserIds: _shadowUserIds(ref, event.groupId),
    );
    final participantsAsync = AsyncValue.data(participants);
    // #289: distinguish two same-named members exactly where money is split.
    final displayNames = MemberNameResolver.disambiguateEventParticipants(
      event,
    );

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
        SizedBox(height: context.spacing.space12),
        Container(
          padding: EdgeInsets.all(context.spacing.space8),
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
                  padding: EdgeInsets.all(context.spacing.space16),
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
                    displayName:
                        displayNames[participant.id] ??
                        participant.displayName ??
                        context.l10n.editorUnknownParticipant,
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
  // #289: disambiguated render name (id-keyed callbacks are unaffected).
  final String displayName;
  final bool isSelected;
  final VoidCallback onToggle;

  const _ParticipantTile({
    required this.participant,
    required this.displayName,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: context.spacing.space8),
      leading: RAvatar(name: displayName, size: 36),
      title: Text(
        displayName,
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
    // #278: mark placeholder ("shadow") members not yet joined.
    final participants = _eventParticipants(
      event,
      shadowUserIds: _shadowUserIds(ref, event.groupId),
    );
    // #289: distinguish two same-named members in the "who paid" picker.
    final displayNames = MemberNameResolver.disambiguateEventParticipants(
      event,
    );

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
        SizedBox(height: context.spacing.space12),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: context.spacing.space16,
            vertical: context.spacing.space4,
          ),
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
                final name =
                    displayNames[p.id] ??
                    p.displayName ??
                    context.l10n.editorUnknownParticipant;
                return DropdownMenuItem(
                  value: p.id,
                  child: Row(
                    children: [
                      RAvatar(name: name, size: 28),
                      SizedBox(width: context.spacing.space12),
                      Expanded(
                        child: Text(
                          isMe ? context.l10n.editorParticipantMe(name) : name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: isMe
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      // #278: flag a placeholder member who hasn't joined yet.
                      if (p.isShadow) ...[
                        SizedBox(width: context.spacing.space8),
                        Text(
                          context.l10n.editorShadowProfile,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ],
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
