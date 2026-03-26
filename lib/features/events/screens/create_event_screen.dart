import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../groups/models/group_member_model.dart';
import '../../groups/providers/group_provider.dart';
import '../models/event_model.dart';
import '../models/event_type_config.dart';
import '../providers/event_provider.dart';

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
      await ref.read(eventServiceProvider).createEvent(
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
      // Pop both CreateEventScreen and EventTypePickerScreen (D-05)
      // TODO(Plan 03-04): Navigate to EventCommandCenter after creation
      Navigator.of(context)
        ..pop()
        ..pop();
    } catch (e) {
      debugPrint('[CreateEventScreen] Create event error: $e');
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('New ${typeConfig.label} Event'),
      ),
      body: membersAsync.when(
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

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
                horizontal: AppColors.space24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppColors.space32),

                  // --- Event Name ---
                  Text(
                    'Event Name',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppColors.space8),
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

                  const SizedBox(height: AppColors.space24),

                  // --- Dates ---
                  Row(
                    children: [
                      Text(
                        'Dates',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(width: AppColors.space8),
                      Text(
                        '(optional)',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppColors.space8),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    AppColors.radiusMedium),
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
                      const SizedBox(width: AppColors.space12),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    AppColors.radiusMedium),
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

                  const SizedBox(height: AppColors.space24),

                  // --- Participants ---
                  Text(
                    'Participants',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppColors.space8),
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

                  // --- Module Toggles (Custom type only, per D-14) ---
                  if (widget.eventType == EventType.custom) ...[
                    const SizedBox(height: AppColors.space24),
                    Text(
                      'Modules',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppColors.space8),
                    _ModuleToggleRow(
                      icon: Iconsax.dollar_circle,
                      label: 'Ledger',
                      color: AppColors.emerald,
                      value: _modules.ledger,
                      onChanged: (v) => setState(
                        () => _modules = _modules.copyWith(ledger: v),
                      ),
                    ),
                    _ModuleToggleRow(
                      icon: Iconsax.bag,
                      label: 'Gear',
                      color: AppColors.amber,
                      value: _modules.gear,
                      onChanged: (v) => setState(
                        () => _modules = _modules.copyWith(gear: v),
                      ),
                    ),
                    _ModuleToggleRow(
                      icon: Iconsax.car,
                      label: 'Logistics',
                      color: AppColors.sky,
                      value: _modules.logistics,
                      onChanged: (v) => setState(
                        () => _modules = _modules.copyWith(logistics: v),
                      ),
                    ),
                    _ModuleToggleRow(
                      icon: Iconsax.folder,
                      label: 'Vault',
                      color: AppColors.indigo,
                      value: _modules.vault,
                      onChanged: (v) => setState(
                        () => _modules = _modules.copyWith(vault: v),
                      ),
                    ),
                    _ModuleToggleRow(
                      icon: Iconsax.image,
                      label: 'Memories',
                      color: AppColors.mint,
                      value: _modules.memories,
                      onChanged: (v) => setState(
                        () => _modules = _modules.copyWith(memories: v),
                      ),
                    ),
                  ],

                  const SizedBox(height: 48),

                  // --- Submit button ---
                  LoadingButton(
                    label:
                        isLoading ? 'Creating\u2026' : 'Create Event',
                    isLoading: isLoading,
                    onPressed: () => _submitForm(members),
                  ),

                  const SizedBox(height: AppColors.space32),
                ],
              ),
            ),
          );
        },
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
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            // Avatar placeholder
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: AppColors.surfaceLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Iconsax.user,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: AppColors.space12),
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
                    ? AppColors.primary
                    : null,
              ),
              onChanged: (v) => onToggle(v ?? isSelected),
            ),
          ],
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
          const SizedBox(width: AppColors.space12),
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
                  ? AppColors.primary
                  : null,
            ),
            trackColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? AppColors.primary.withValues(alpha: 0.3)
                  : null,
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
