import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/error_widgets.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../events/models/event_model.dart';
import '../../groups/providers/group_provider.dart';
import '../../groups/services/member_name_resolver.dart';
import '../../trip/models/trip_model.dart';

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
  final members =
      ref.watch(groupMembersProvider(groupId)).valueOrNull ?? const [];
  return {
    for (final m in members)
      if (m.isShadow) m.userId,
  };
}

/// Multi-select participant list for custom ("Some people") splits. #485 moved
/// this inline into the unified `SplitCard`; it is shown only when the scope
/// segment is on "Some people". The old combined `SplitScopeSelector` (scope
/// tabs + this roster + a second payer dropdown) was retired — the payer is now
/// a single control on the card, and the scope tabs are the card's segment.
class CustomParticipantSelector extends ConsumerWidget {
  final Event event;
  final Set<String> customSplitParticipants;
  final ValueChanged<Set<String>> onCustomSplitChanged;

  const CustomParticipantSelector({
    super.key,
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
