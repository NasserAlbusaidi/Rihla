import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/tokens/domain_aliases.dart';
import '../../groups/models/group_member_model.dart';
import '../keys/event_keys.dart';

/// Card widget for picking event participants.
///
/// Displays a "Select All" toggle, a divider, then one [_ParticipantRow]
/// per member. All selection state is owned by the parent [CreateEventScreen].
///
/// Extracted from [CreateEventScreen] (Phase 36 ARCH-01 decomposition).
/// Purely presentational — no state, no providers.
class EventParticipantsCard extends StatelessWidget {
  final List<GroupMember> members;
  final Set<String> selectedIds;

  /// Called with the full updated selected-id set when "Select All" changes.
  final ValueChanged<Set<String>> onSelectAllChanged;

  /// Called with a single member's userId when that row is toggled.
  final ValueChanged<String> onToggle;

  const EventParticipantsCard({
    super.key,
    required this.members,
    required this.selectedIds,
    required this.onSelectAllChanged,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.cardSurface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: context.shadows.raised,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Participants',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          // Select All row
          Row(
            children: [
              Expanded(
                child: Text(
                  'Select All',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Checkbox(
                key: EventKeys.selectAllButton,
                value: members.isNotEmpty &&
                    selectedIds.length == members.length,
                checkColor: Colors.white,
                fillColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? context.colors.primary
                      : null,
                ),
                onChanged: (v) {
                  final allIds =
                      Set<String>.from(members.map((m) => m.userId));
                  onSelectAllChanged(
                      Set.unmodifiable(v == true ? allIds : <String>{}));
                },
              ),
            ],
          ),
          const Divider(height: 8),
          ...members.map(
            (member) => _ParticipantRow(
              member: member,
              isSelected: selectedIds.contains(member.userId),
              onToggle: (_) => onToggle(member.userId),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private participant row
// ---------------------------------------------------------------------------

/// A single participant checkbox row in the participant picker.
///
/// Moved from [CreateEventScreen] (Phase 36 ARCH-01 decomposition).
class _ParticipantRow extends StatelessWidget {
  final GroupMember member;
  final bool isSelected;
  final ValueChanged<bool> onToggle;

  const _ParticipantRow({
    required this.member,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: member.displayName,
      checked: isSelected,
      child: GestureDetector(
        onTap: () => onToggle(!isSelected),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              // Avatar placeholder
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: context.colors.inputFill,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Iconsax.user,
                  size: 16,
                  color: context.colors.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  member.displayName,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Checkbox(
                value: isSelected,
                checkColor: Colors.white,
                fillColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? context.colors.primary
                      : null,
                ),
                onChanged: (v) => onToggle(v ?? isSelected),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
