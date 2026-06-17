import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../groups/models/group_member_model.dart';
import '../../groups/services/member_name_resolver.dart';
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
    // #196/#289: distinguish two same-named members in the participant picker
    // (render-only; selection still keys by userId). Former members keep their
    // suffix. The card has no Event, so resolve group-scoped over the roster.
    final displayNames = MemberNameResolver.disambiguate({
      for (final m in members)
        m.userId: MemberDisplay(
          rawName: m.displayName,
          isFormer: m.isTombstone,
        ),
    });

    return Container(
      margin: EdgeInsets.only(bottom: context.spacing.space12),
      padding: EdgeInsets.all(context.spacing.space16),
      decoration: BoxDecoration(
        color: context.colors.cardSurface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: context.shadows.raised,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.eventParticipants,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          SizedBox(height: context.spacing.space8),
          // Select All row
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.eventSelectAll,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Checkbox(
                key: EventKeys.selectAllButton,
                value:
                    members.isNotEmpty && selectedIds.length == members.length,
                checkColor: Colors.white,
                fillColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? context.colors.primary
                      : null,
                ),
                onChanged: (v) {
                  final allIds = Set<String>.from(members.map((m) => m.userId));
                  onSelectAllChanged(
                    Set.unmodifiable(v == true ? allIds : <String>{}),
                  );
                },
              ),
            ],
          ),
          const Divider(height: 8),
          ...members.map(
            (member) => _ParticipantRow(
              displayName: displayNames[member.userId] ?? member.displayName,
              isShadow: member.isShadow,
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
  /// #196/#289 disambiguated render name (selection keys by userId, unaffected).
  final String displayName;

  /// #278: a placeholder member added by name but not yet joined.
  final bool isShadow;
  final bool isSelected;
  final ValueChanged<bool> onToggle;

  const _ParticipantRow({
    required this.displayName,
    required this.isShadow,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: displayName,
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
              SizedBox(width: context.spacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      displayName,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (isShadow)
                      Text(
                        context.l10n.editorShadowProfile,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                  ],
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
