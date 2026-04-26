import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/services/haptic_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../events/models/event_model.dart';
import '../../trip/models/trip_model.dart';
import '../../trip/providers/trip_provider.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

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

/// Payer dropdown for the edit-expense screen. Visible only to the event
/// creator (leader). Non-leaders see a zero-height widget.
///
/// All mutable state (selected payer ID) lives on the parent screen;
/// this widget is stateless and delegates changes via [onPayerChanged].
class EditExpensePayerSelector extends ConsumerWidget {
  final Event event;
  final String eventId;
  final String? selectedPayerId;
  final ValueChanged<String?> onPayerChanged;

  const EditExpensePayerSelector({
    super.key,
    required this.event,
    required this.eventId,
    required this.selectedPayerId,
    required this.onPayerChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentParticipant = ref.watch(currentParticipantProvider(eventId));
    final currentUid = ref.watch(currentUserProvider)?.uid;
    final isLeader =
        currentUid != null && event.createdBy == currentUid;

    if (!isLeader) return const SizedBox.shrink();

    final participants = _eventParticipants(event);
    if (participants.isEmpty) return const SizedBox.shrink();

    final effectivePayerId = selectedPayerId ?? currentParticipant?.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PAID BY',
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
                  child: Text(
                    isMe
                        ? '${p.displayName ?? 'Unknown'} (Me)'
                        : p.displayName ?? 'Unknown',
                  ),
                );
              }).toList(),
              onChanged: (v) {
                HapticService.lightClick();
                onPayerChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}
