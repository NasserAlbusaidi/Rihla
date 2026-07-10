import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/app_messenger.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/calendar_date.dart';
import '../../../core/utils/error_message_translator.dart';
import '../../../core/utils/write_ack.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../../shared/widgets/module_header.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../groups/models/group_member_model.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../keys/event_keys.dart';
import '../models/event_model.dart';
import '../models/event_type_config.dart';
import '../providers/event_provider.dart';
import '../utils/event_display.dart';
import '../widgets/event_details_card.dart';
import '../widgets/event_participants_card.dart';

/// Event creation form — a single screen (the standalone type-picker was folded
/// in as a chip row, #489).
///
/// Orchestrates form state and submission. Visual sections:
/// - `_TypeChipRow` — the event type selector (replaces the old picker screen)
/// - [EventDetailsCard] — name field + date pickers
/// - [EventParticipantsCard] — participant picker
///
/// On submit: calls [EventService.createEvent], then navigates to the new
/// event hub so back returns to group detail, not the form (D-06/Pitfall 2).
///
/// Per D-02, D-03, D-04 and UI-SPEC CreateEventScreen component.
class CreateEventScreen extends ConsumerStatefulWidget {
  final String groupId;
  final EventType initialEventType;

  const CreateEventScreen({
    super.key,
    required this.groupId,
    required this.initialEventType,
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

  /// The currently-selected event type — mutable via the type chip-row (#489).
  /// Seeded from [CreateEventScreen.initialEventType], coercing the only
  /// non-selectable value (custom) to the default so a cold deep link to
  /// `/create-event/custom` still lands on a valid, visibly-selected chip.
  late EventType _selectedType;

  /// Module config — kept in sync with [_selectedType]. Inert since Phase 39
  /// ([EventModules.forType] always yields ledger-only); retained for parity.
  late EventModules _modules;

  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialEventType == EventType.custom
        ? EventType.trip
        : widget.initialEventType;
    _modules = EventModules.forType(_selectedType);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Form submission
  // ---------------------------------------------------------------------------

  String? _resolveCurrentUid() {
    final providerUid = ref.read(currentUserIdProvider);
    if (providerUid != null && providerUid.isNotEmpty) return providerUid;

    try {
      final firebaseUid = FirebaseConfig.currentUser?.uid;
      return firebaseUid != null && firebaseUid.isNotEmpty ? firebaseUid : null;
    } catch (_) {
      // Firebase can be uninitialized in widget tests that override identity.
      return null;
    }
  }

  Future<void> _submitForm(List<GroupMember> members) async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedParticipantIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.eventSelectAtLeastOneParticipant),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    ref.read(eventErrorProvider.notifier).state = null;

    // Build participantNames map from selected members (immutable pattern)
    final participantNames = Map<String, String>.unmodifiable({
      for (final m in members)
        if (_selectedParticipantIds.contains(m.userId)) m.userId: m.displayName,
    });

    final uid = _resolveCurrentUid();
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.eventCreateFailed),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    final connectivity = ref.read(connectivityProvider.notifier);
    final connectivityStatus = ref.read(connectivityProvider);
    ref.read(eventLoadingProvider.notifier).state = true;

    try {
      // #412/#516: the write future acks only when the SERVER confirms — offline
      // it stays pending until reconnect. Stage the write (local cache + queued
      // replay) and race the ack, instead of awaiting it raw (which stranded the
      // "Creating…" spinner forever offline).
      final staged = ref
          .read(eventServiceProvider)
          .stageEvent(
            groupId: widget.groupId,
            name: _nameController.text.trim(),
            type: _selectedType,
            participantIds: List.unmodifiable(_selectedParticipantIds.toList()),
            participantNames: participantNames,
            createdBy: uid,
            startDate: _startDate,
            endDate: _endDate,
            // Pass Custom-type module overrides; null for preset types (D-14)
            modules: _selectedType == EventType.custom ? _modules : null,
          );
      final outcome = await awaitServerAck(
        staged.ack,
        skipWait: connectivityStatus != ConnectivityStatus.online,
      );
      if (!mounted) return;
      final event = staged.event;

      if (outcome == WriteAck.acked) {
        connectivity.noteLocalWrite(
          groupId: widget.groupId,
        ); // #357: stale-offline correction
      } else {
        connectivity.noteQueuedWrite(
          groupId: widget.groupId,
        ); // #412: queued — force "will sync"
      }

      // Log event_created activity (D-14) — fire-and-forget, no await
      try {
        final actorName = ref.read(settingsProvider).deviceName.isNotEmpty
            ? ref.read(settingsProvider).deviceName
            : 'Someone';
        ref
            .read(groupActivityServiceProvider)
            .logGroupEvent(
              groupId: widget.groupId,
              type: 'event_created',
              actorId: uid,
              actorName: actorName,
              description: 'created ${event.name}',
              metadata: {'eventId': event.id, 'eventName': event.name},
            );
      } catch (_) {
        // Activity logging failure must never crash the creation flow.
      }

      if (outcome == WriteAck.queued) {
        // The queued "will sync" feedback uses the GLOBAL messenger: the
        // context.go below replaces this screen, tearing down its local
        // ScaffoldMessenger before a local snackbar could ever be seen (#516).
        appMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(context.l10n.eventCreatedWillSync),
            duration: const Duration(seconds: 4),
          ),
        );
      }

      // context.go replaces the entire creation stack, navigating to the new
      // event hub. Back button returns to group detail, not the form (D-06/Pitfall 2).
      context.go('/group/${widget.groupId}/event/${event.id}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.eventCreateFailed),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) ref.read(eventLoadingProvider.notifier).state = false;
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
    if (picked != null) {
      setState(() => _startDate = anchorCalendarDate(picked));
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _endDate = anchorCalendarDate(picked));
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(eventLoadingProvider);
    final membersAsync = ref.watch(groupMembersProvider(widget.groupId));
    final groupName = ref
        .watch(groupDetailProvider(widget.groupId))
        .valueOrNull
        ?.name;

    return Scaffold(
      key: EventKeys.createEventScreen,
      backgroundColor: context.colors.scaffoldBackground,
      body: Column(
        children: [
          ModuleHeader(
            useDarkTheme: true,
            title: context.l10n.eventNew,
            subtitle: groupName,
          ),
          const OfflineBanner(),
          Expanded(
            child: membersAsync.when(
              // #488: layout-matched skeleton + a real error state, not a bare
              // spinner / naked Text.
              loading: SkeletonLoader.cardList,
              error: (err, _) => EmptyStateView(
                icon: Iconsax.warning_2,
                title: context.l10n.groupMembersLoadFailed,
                message: friendlyMessageFor(context, err),
                actionLabel: context.l10n.commonRetry,
                onAction: () =>
                    ref.invalidate(groupMembersProvider(widget.groupId)),
              ),
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

                final disableAnimations = MediaQuery.of(
                  context,
                ).disableAnimations;

                final chipRow = _TypeChipRow(
                  selectedType: _selectedType,
                  onSelect: (type) {
                    HapticService.selection();
                    setState(() {
                      _selectedType = type;
                      _modules = EventModules.forType(type);
                    });
                  },
                );

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
                    final updated = Set<String>.from(_selectedParticipantIds);
                    if (updated.contains(userId)) {
                      updated.remove(userId);
                    } else {
                      updated.add(userId);
                    }
                    setState(
                      () => _selectedParticipantIds = Set.unmodifiable(updated),
                    );
                  },
                );

                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.spacing.space16,
                    vertical: context.spacing.space16,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // #245: every group is born with one seeded event, so
                        // anyone here is adding a SECOND one — teach when
                        // that's worth it.
                        Padding(
                          padding: EdgeInsetsDirectional.only(
                            bottom: context.spacing.space12,
                          ),
                          child: Text(
                            context.l10n.eventSecondEventHint,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: context.colors.textSecondary,
                                ),
                          ),
                        ),

                        // Event type chip-row — subtle animation
                        if (disableAnimations)
                          chipRow
                        else
                          chipRow
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
                          label: isLoading
                              ? context.l10n.eventCreating
                              : context.l10n.eventCreate,
                          isLoading: isLoading,
                          onPressed: () => _submitForm(members),
                        ),

                        SizedBox(height: context.spacing.space32),
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

/// Horizontal, scrollable row of selectable event-type chips (#489) — replaces
/// the standalone type-picker screen. Custom is excluded (see
/// [EventTypeConfig.selectableTypes]). Scrolls so 4 chips / long Arabic labels
/// never overflow.
class _TypeChipRow extends StatelessWidget {
  const _TypeChipRow({required this.selectedType, required this.onSelect});

  final EventType selectedType;
  final ValueChanged<EventType> onSelect;

  @override
  Widget build(BuildContext context) {
    final types = EventTypeConfig.selectableTypes;
    return Padding(
      padding: EdgeInsets.only(bottom: context.spacing.space12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final config in types)
              Padding(
                padding: EdgeInsetsDirectional.only(
                  end: context.spacing.space8,
                ),
                child: _TypeChip(
                  config: config,
                  selected: config.type == selectedType,
                  onTap: () => onSelect(config.type),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single pill chip: icon + localized label. Selected → saffron-tint fill +
/// saffron border (the design-system Chip convention). Tappable; carries the
/// `eventTypeCard` key + a `selected` semantics flag for tests.
class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.config,
    required this.selected,
    required this.onTap,
  });

  final EventTypeConfig config;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = selected ? colors.primary : colors.textSecondary;

    return Semantics(
      button: true,
      selected: selected,
      label: config.type.localizedLabel(context.l10n),
      child: GestureDetector(
        key: EventKeys.eventTypeCard(config.label),
        onTap: onTap,
        child: Container(
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: context.spacing.space16,
            vertical: context.spacing.space12,
          ),
          decoration: BoxDecoration(
            color: selected ? colors.saffronTint : colors.cardSurface,
            borderRadius: BorderRadius.circular(context.spacing.radiusPill),
            border: Border.all(
              color: selected ? colors.primary : colors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(config.icon, size: 16, color: accent),
              SizedBox(width: context.spacing.space8),
              Text(
                config.type.localizedLabel(context.l10n),
                style: AppTypography.sans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
