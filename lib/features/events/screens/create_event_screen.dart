import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/module_header.dart';
import '../../groups/models/group_member_model.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../keys/event_keys.dart';
import '../models/event_model.dart';
import '../models/event_type_config.dart';
import '../providers/event_provider.dart';
import '../widgets/event_details_card.dart';
import '../widgets/event_participants_card.dart';
import '../widgets/event_type_badge.dart';

/// Event creation form — Step 2 of the event creation flow.
///
/// Orchestrates form state and submission. Visual sections are delegated to:
/// - [EventTypeBadge] — type pill
/// - [EventDetailsCard] — name field + date pickers
/// - [EventParticipantsCard] — participant picker
///
/// On submit: calls [EventService.createEvent], then navigates to the new
/// event hub so back returns to group detail, not the form (D-06/Pitfall 2).
///
/// Per D-02, D-03, D-04 and UI-SPEC CreateEventScreen component.
class CreateEventScreen extends ConsumerStatefulWidget {
  final String groupId;
  final EventType eventType;

  const CreateEventScreen({
    super.key,
    required this.groupId,
    required this.eventType,
  });

  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  /// IDs of selected participants — initialized with all member user IDs (D-04).
  Set<String> _selectedParticipantIds = {};

  /// Whether participants have been pre-populated from the provider.
  bool _participantsInitialized = false;

  /// Module config — initialized from [EventModules.forType] for this type.
  late EventModules _modules;

  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _modules = EventModules.forType(widget.eventType);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Form submission
  // ---------------------------------------------------------------------------

  Future<void> _submitForm(List<GroupMember> members) async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedParticipantIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least one participant.'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    ref.read(eventLoadingProvider.notifier).state = true;
    ref.read(eventErrorProvider.notifier).state = null;

    // Build participantNames map from selected members (immutable pattern)
    final participantNames = Map<String, String>.unmodifiable({
      for (final m in members)
        if (_selectedParticipantIds.contains(m.userId)) m.userId: m.displayName,
    });

    // Current Firebase UID for createdBy
    final uid = FirebaseConfig.currentUser?.uid ?? '';

    try {
      final event = await ref.read(eventServiceProvider).createEvent(
            groupId: widget.groupId,
            name: _nameController.text.trim(),
            type: widget.eventType,
            participantIds:
                List.unmodifiable(_selectedParticipantIds.toList()),
            participantNames: participantNames,
            createdBy: uid,
            startDate: _startDate,
            endDate: _endDate,
            // Pass Custom-type module overrides; null for preset types (D-14)
            modules: widget.eventType == EventType.custom ? _modules : null,
          );
      if (!mounted) return;
      ref.read(eventLoadingProvider.notifier).state = false;

      // Log event_created activity (D-14) — fire-and-forget, no await
      try {
        final actorId = FirebaseConfig.currentUser?.uid ?? '';
        final actorName = ref.read(settingsProvider).deviceName.isNotEmpty
            ? ref.read(settingsProvider).deviceName
            : 'Someone';
        ref.read(groupActivityServiceProvider).logGroupEvent(
          groupId: widget.groupId,
          type: 'event_created',
          actorId: actorId,
          actorName: actorName,
          description: 'created ${event.name}',
          metadata: {'eventId': event.id, 'eventName': event.name},
        );
      } catch (_) {
        // Activity logging failure must never crash the creation flow.
      }

      // context.go replaces the entire creation stack, navigating to the new
      // event hub. Back button returns to group detail, not the form (D-06/Pitfall 2).
      context.go('/group/${widget.groupId}/event/${event.id}');
    } catch (e) {
      if (!mounted) return;
      ref.read(eventLoadingProvider.notifier).state = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't create event. Check your connection and try again.",
          ),
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Date pickers
  // ---------------------------------------------------------------------------

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final typeConfig = EventTypeConfig.forType(widget.eventType);
    final isLoading = ref.watch(eventLoadingProvider);
    final membersAsync = ref.watch(groupMembersProvider(widget.groupId));

    return Scaffold(
      key: EventKeys.createEventScreen,
      backgroundColor: context.colors.scaffoldBackground,
      body: Column(
        children: [
          ModuleHeader(
            useDarkTheme: true,
            title: typeConfig.label,
          ),
          Expanded(
            child: membersAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error: $err')),
              data: (members) {
                // Pre-populate participant selection once on first data load (D-04)
                if (!_participantsInitialized && members.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _selectedParticipantIds = Set.unmodifiable(
                          members.map((m) => m.userId).toSet(),
                        );
                        _participantsInitialized = true;
                      });
                    }
                  });
                }

                final disableAnimations =
                    MediaQuery.of(context).disableAnimations;

                final badge = EventTypeBadge(typeConfig: typeConfig);

                final detailsCard = EventDetailsCard(
                  nameController: _nameController,
                  startDate: _startDate,
                  endDate: _endDate,
                  onPickStartDate: _pickStartDate,
                  onPickEndDate: _pickEndDate,
                );

                final participantsCard = EventParticipantsCard(
                  members: members,
                  selectedIds: _selectedParticipantIds,
                  onSelectAllChanged: (ids) =>
                      setState(() => _selectedParticipantIds = ids),
                  onToggle: (userId) {
                    // Immutable set update
                    final updated =
                        Set<String>.from(_selectedParticipantIds);
                    if (updated.contains(userId)) {
                      updated.remove(userId);
                    } else {
                      updated.add(userId);
                    }
                    setState(
                      () => _selectedParticipantIds =
                          Set.unmodifiable(updated),
                    );
                  },
                );

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Event type badge — subtle animation
                        if (disableAnimations)
                          badge
                        else
                          badge
                              .animate()
                              .fadeIn(delay: 60.ms)
                              .slideY(begin: 0.05),

                        // Event Details card
                        if (disableAnimations)
                          detailsCard
                        else
                          detailsCard
                              .animate()
                              .fadeIn(delay: 100.ms)
                              .slideY(begin: 0.1),

                        // Participants card
                        if (disableAnimations)
                          participantsCard
                        else
                          participantsCard
                              .animate()
                              .fadeIn(delay: 200.ms)
                              .slideY(begin: 0.1),

                        // --- Submit button ---
                        LoadingButton(
                          key: EventKeys.createEventButton,
                          label: isLoading ? 'Creating\u2026' : 'Create Event',
                          isLoading: isLoading,
                          onPressed: () => _submitForm(members),
                        ),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
