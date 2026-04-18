import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/error_widgets.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../events/providers/event_provider.dart';
import '../../trip/models/trip_model.dart';
import '../models/sub_group_model.dart';
import '../providers/sub_group_provider.dart';

/// Bottom-sheet member assignment UI for the Logistics screen.
///
/// Shows the list of unassigned participants for [subGroup]. Tapping a
/// participant calls [onMemberSelected] with the chosen [Participant] and
/// pops the sheet. Calling code (the screen) issues the actual addMember call.
class LogisticsMemberPickerSheet extends ConsumerWidget {
  final SubGroup subGroup;
  final String groupId;
  final String eventId;

  /// Called when the user selects a participant. The sheet pops itself before
  /// invoking this callback — the caller handles the mutation.
  final void Function(Participant participant) onMemberSelected;

  const LogisticsMemberPickerSheet({
    super.key,
    required this.subGroup,
    required this.groupId,
    required this.eventId,
    required this.onMemberSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventRef = (groupId: groupId, eventId: eventId);
    final allGroupsAsync = ref.watch(eventSubGroupsProvider(eventRef));

    // Derive participant list from eventLogisticsParticipantsProvider.
    // We need the Event object — read eventDetailProvider synchronously.
    final eventAsync = ref.watch(
      eventDetailProvider((groupId: groupId, eventId: eventId)),
    );
    final event = eventAsync.valueOrNull;
    final participants = event != null
        ? ref.watch(eventLogisticsParticipantsProvider(event))
        : <Participant>[];

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      decoration: BoxDecoration(
        color: context.colors.cardSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'SELECT MEMBER',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: context.colors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          allGroupsAsync.when(
            data: (groups) {
              final assignedUserIds = groups
                  .expand((g) => g.members)
                  .map((m) => m.participantId)
                  .toSet();

              final unassigned = participants
                  .where((p) => !assignedUserIds.contains(p.id))
                  .toList();

              if (unassigned.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      'No unassigned members',
                      style: TextStyle(color: context.colors.textSecondary),
                    ),
                  ),
                );
              }

              return Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: unassigned.length,
                  itemBuilder: (context, index) {
                    final p = unassigned[index];
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: context.colors.scaffoldBackground,
                        backgroundImage: p.avatarUrl != null &&
                                p.avatarUrl!.startsWith('http')
                            ? NetworkImage(p.avatarUrl!)
                            : null,
                        child: p.avatarUrl == null ||
                                !p.avatarUrl!.startsWith('http')
                            ? Text(
                                p.displayName?[0] ?? 'U',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: context.colors.moduleLedger,
                                ),
                              )
                            : null,
                      ),
                      title: Text(
                        p.displayName ?? 'Unknown',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onTap: () {
                        HapticService.lightClick();
                        Navigator.pop(context);
                        onMemberSelected(p);
                      },
                    );
                  },
                ),
              );
            },
            loading: () => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Loading...',
                  style: TextStyle(color: context.colors.textSecondary),
                ),
              ),
            ),
            error: (e, _) => const InlineErrorWidget(message: 'Unable to load'),
          ),
        ],
      ),
    );
  }
}
