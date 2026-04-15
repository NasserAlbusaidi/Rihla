import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/module_header.dart';
import '../../groups/models/group_member_model.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../models/event_model.dart';
import '../keys/event_keys.dart';
import '../models/event_type_config.dart';
import '../providers/event_provider.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';

/// Event creation form — Step 2 of the event creation flow.
///
/// Collects event name (required), optional start/end dates, participant
/// picker (all pre-checked), and module toggles for Custom events only.
///
/// On submit: calls [EventService.createEvent], then pops both creation
/// screens (picker + form) so the user returns to [GroupDetailScreen].
///
/// Per D-02, D-03, D-04, D-14 and UI-SPEC CreateEventScreen component.
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

    // Inherit currency from group (D-03)
    final currency =
        ref.read(groupDetailProvider(widget.groupId)).valueOrNull?.currency ??
            'OMR';

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
            currency: currency,
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
      backgroundColor: AppColorTokens.light.scaffoldBackground,
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

                // --- Event type badge ---
                final eventTypeBadge = Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: typeConfig.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      Icon(typeConfig.icon,
                          size: 20, color: typeConfig.color),
                      const SizedBox(width: 8),
                      Text(
                        typeConfig.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: typeConfig.color,
                        ),
                      ),
                    ],
                  ),
                );

                // --- Event Details card ---
                final eventDetailsCard = Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColorTokens.light.cardSurface,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: AppShadowTokens.standard.raised,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- Event Name ---
                      Text(
                        'Event Name',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'e.g. Summer camping trip',
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty
                                ? "Event name can't be empty."
                                : null,
                      ),

                      const SizedBox(height: 24),

                      // --- Dates ---
                      Row(
                        children: [
                          Text(
                            'Dates',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '(optional)',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: AppColorTokens.light.textMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: _pickStartDate,
                                child: Text(
                                  _startDate != null
                                      ? DateFormat('MMM d, yyyy')
                                          .format(_startDate!)
                                      : 'Start date',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: _pickEndDate,
                                child: Text(
                                  _endDate != null
                                      ? DateFormat('MMM d, yyyy')
                                          .format(_endDate!)
                                      : 'End date',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );

                // --- Participants card ---
                final participantsCard = Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColorTokens.light.cardSurface,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: AppShadowTokens.standard.raised,
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
                                _selectedParticipantIds.length ==
                                    members.length,
                            checkColor: Colors.white,
                            fillColor: WidgetStateProperty.resolveWith(
                              (states) =>
                                  states.contains(WidgetState.selected)
                                      ? AppColorTokens.light.primary
                                      : null,
                            ),
                            onChanged: (v) {
                              final allIds = Set<String>.from(
                                  members.map((m) => m.userId));
                              setState(
                                () => _selectedParticipantIds =
                                    Set.unmodifiable(
                                        v == true ? allIds : <String>{}),
                              );
                            },
                          ),
                        ],
                      ),
                      const Divider(height: 8),
                      ...members.map(
                        (member) => _ParticipantRow(
                          member: member,
                          isSelected: _selectedParticipantIds
                              .contains(member.userId),
                          onToggle: (selected) {
                            // Immutable set update
                            final updated = Set<String>.from(
                                _selectedParticipantIds);
                            if (selected) {
                              updated.add(member.userId);
                            } else {
                              updated.remove(member.userId);
                            }
                            setState(
                              () => _selectedParticipantIds =
                                  Set.unmodifiable(updated),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );

                // --- Module Toggles card (Custom type only, per D-14) ---
                final modulesCard = widget.eventType == EventType.custom
                    ? Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColorTokens.light.cardSurface,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: AppShadowTokens.standard.raised,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Modules',
                              key: EventKeys.modulesSection,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            _ModuleToggleRow(
                              key: EventKeys.moduleLedgerToggle,
                              icon: Iconsax.dollar_circle,
                              label: 'Ledger',
                              color: AppColorTokens.light.success,
                              value: _modules.ledger,
                              onChanged: (v) => setState(
                                () => _modules = _modules.copyWith(ledger: v),
                              ),
                            ),
                            _ModuleToggleRow(
                              key: EventKeys.moduleGearToggle,
                              icon: Iconsax.bag,
                              label: 'Gear',
                              color: AppColorTokens.light.warning,
                              value: _modules.gear,
                              onChanged: (v) => setState(
                                () => _modules = _modules.copyWith(gear: v),
                              ),
                            ),
                            _ModuleToggleRow(
                              key: EventKeys.moduleLogisticsToggle,
                              icon: Iconsax.car,
                              label: 'Logistics',
                              color: AppColorTokens.light.textSecondary,
                              value: _modules.logistics,
                              onChanged: (v) => setState(
                                () => _modules =
                                    _modules.copyWith(logistics: v),
                              ),
                            ),
                            _ModuleToggleRow(
                              key: EventKeys.moduleVaultToggle,
                              icon: Iconsax.folder,
                              label: 'Vault',
                              color: AppColorTokens.light.textSecondary,
                              value: _modules.vault,
                              onChanged: (v) => setState(
                                () => _modules = _modules.copyWith(vault: v),
                              ),
                            ),
                            _ModuleToggleRow(
                              key: EventKeys.moduleMemoriesToggle,
                              icon: Iconsax.image,
                              label: 'Memories',
                              color: AppColorTokens.light.primary,
                              value: _modules.memories,
                              onChanged: (v) => setState(
                                () => _modules =
                                    _modules.copyWith(memories: v),
                              ),
                            ),
                          ],
                        ),
                      )
                    : null;

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
                          eventTypeBadge
                        else
                          eventTypeBadge
                              .animate()
                              .fadeIn(delay: 60.ms)
                              .slideY(begin: 0.05),

                        // Event Details card
                        if (disableAnimations)
                          eventDetailsCard
                        else
                          eventDetailsCard
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

                        // Modules card (custom only)
                        if (modulesCard != null)
                          if (disableAnimations)
                            modulesCard
                          else
                            modulesCard
                                .animate()
                                .fadeIn(delay: 300.ms)
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

// ---------------------------------------------------------------------------
// Participant row widget
// ---------------------------------------------------------------------------

/// A single participant checkbox row in the participant picker.
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
                  color: AppColorTokens.light.inputFill,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Iconsax.user,
                  size: 16,
                  color: AppColorTokens.light.textSecondary,
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
                      ? AppColorTokens.light.primary
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

// ---------------------------------------------------------------------------
// Module toggle row widget
// ---------------------------------------------------------------------------

/// A single module toggle row for Custom event type (D-14).
class _ModuleToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ModuleToggleRow({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Switch(
            value: value,
            thumbColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? AppColorTokens.light.primary
                  : null,
            ),
            trackColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? AppColorTokens.light.primary.withValues(alpha: 0.3)
                  : null,
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
