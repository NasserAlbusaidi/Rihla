import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/module_header.dart';
import '../keys/group_keys.dart';
import '../models/group_activity_log_model.dart';
import '../providers/group_balance_provider.dart';
import '../providers/group_provider.dart';
import '../widgets/group_activity_tile.dart';

/// Full-screen paginated group activity timeline (D-07, D-08, D-09, D-10, D-11).
///
/// Features:
/// - ModuleHeader with dark gradient (D-07)
/// - Date-grouped section headers: TODAY, YESTERDAY, MMM d (D-08)
/// - Rich card tiles via GroupActivityTile (D-09)
/// - Client-side filter chips: All / Settlements / Events / Members (D-10)
/// - Infinite scroll — no "Load more" button (D-11)
class GroupActivityScreen extends ConsumerStatefulWidget {
  final String groupId;

  const GroupActivityScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupActivityScreen> createState() =>
      _GroupActivityScreenState();
}

class _GroupActivityScreenState extends ConsumerState<GroupActivityScreen> {
  final List<GroupActivityLog> _activities = [];
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  String _activeFilter = 'All';
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _loadPage();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Triggers next page load when within 200px of bottom.
  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200 &&
        _hasMore &&
        !_isLoadingMore) {
      _loadPage();
    }
  }

  /// Fetches the next page of activity entries using cursor-based pagination.
  ///
  /// Guards against concurrent calls via [_isLoadingMore]. Sets [_hasMore]
  /// to false when fewer than 50 entries are returned (end of stream).
  Future<void> _loadPage() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final service = ref.read(groupActivityServiceProvider);
      final snap = await service.fetchActivityPageRaw(
        widget.groupId,
        startAfter: _lastDocument,
        limit: 50,
      );

      final newActivities = snap.docs
          .map(
            (doc) =>
                GroupActivityLog.fromFirestore({...doc.data(), 'id': doc.id}),
          )
          .toList();

      setState(() {
        _activities.addAll(newActivities);
        _lastDocument =
            snap.docs.isNotEmpty ? snap.docs.last : _lastDocument;
        _hasMore = snap.docs.length == 50;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() => _isLoadingMore = false);
    }
  }

  /// Client-side filtered view of [_activities] based on [_activeFilter].
  ///
  /// IMPORTANT: Never modify [_activities] directly. [_hasMore] uses raw
  /// count, not filtered count (see RESEARCH Pitfall 3).
  List<GroupActivityLog> get _filteredActivities {
    if (_activeFilter == 'All') return _activities;
    return _activities.where((a) {
      return switch (_activeFilter) {
        'Settlements' => a.type == 'group_settlement',
        'Events' => a.type == 'event_created' || a.type == 'event_deleted',
        'Members' => a.type == 'member_joined' || a.type == 'member_left',
        _ => true,
      };
    }).toList();
  }

  /// Groups activity logs by date label (TODAY, YESTERDAY, or formatted date).
  Map<String, List<GroupActivityLog>> _groupByDate(
      List<GroupActivityLog> logs) {
    final grouped = <String, List<GroupActivityLog>>{};
    final now = DateTime.now();
    for (final log in logs) {
      final label = _dateLabel(log.timestamp, now);
      grouped.putIfAbsent(label, () => []).add(log);
    }
    return grouped;
  }

  String _dateLabel(DateTime date, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final logDate = DateTime(date.year, date.month, date.day);
    if (logDate == today) return 'TODAY';
    if (logDate == today.subtract(const Duration(days: 1))) return 'YESTERDAY';
    return DateFormat('MMM d').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));
    final groupName = groupAsync.valueOrNull?.name;

    return Scaffold(
      key: GroupKeys.activityScreen,
      backgroundColor: AppColorTokens.light.scaffoldBackground,
      body: Column(
        children: [
          ModuleHeader(
            title: 'Activity',
            subtitle: groupName,
            useDarkTheme: true,
          ),
          _buildFilterChips(),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  /// Horizontal filter chip row (D-10).
  Widget _buildFilterChips() {
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip('All', GroupKeys.activityFilterAll),
              const SizedBox(width: 8),
              _buildFilterChip(
                  'Settlements', GroupKeys.activityFilterSettlements),
              const SizedBox(width: 8),
              _buildFilterChip('Events', GroupKeys.activityFilterEvents),
              const SizedBox(width: 8),
              _buildFilterChip('Members', GroupKeys.activityFilterMembers),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, Key key) {
    final isSelected = _activeFilter == label;
    return GestureDetector(
      key: key,
      onTap: () {
        HapticService.selection();
        setState(() => _activeFilter = label);
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColorTokens.light.selectionFill
              : AppColorTokens.light.inputFill,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(
                  color: AppColorTokens.light.primary,
                  width: 1.5,
                )
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isSelected
                  ? AppColorTokens.light.textPrimary
                  : AppColorTokens.light.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    // Loading first page
    if (_isLoadingMore && _activities.isEmpty) {
      return _buildSkeleton();
    }

    final filtered = _filteredActivities;

    // Empty state — no activities at all
    if (_activities.isEmpty) {
      return const EmptyStateView(
        icon: Iconsax.activity,
        title: 'No activity yet',
        message:
            'Group events, payments, and member changes will appear here.',
      );
    }

    // Empty state — filter has no results
    if (filtered.isEmpty) {
      return EmptyStateView(
        icon: Iconsax.search_normal,
        title: 'No ${_activeFilter.toLowerCase()} activity',
        message: 'Try selecting a different filter.',
      );
    }

    final grouped = _groupByDate(filtered);

    // Build flat items list: interleave date labels with activity logs
    final flatItems = <dynamic>[];
    for (final entry in grouped.entries) {
      flatItems.add(entry.key); // date label String
      flatItems.addAll(entry.value); // GroupActivityLog entries
    }
    if (_hasMore) flatItems.add('__loading__');

    // Track overall index for stagger animation (reset per section)
    int tileIndex = 0;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: flatItems.length,
      itemBuilder: (context, index) {
        final item = flatItems[index];

        // Loading sentinel at bottom
        if (item == '__loading__') {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColorTokens.light.primary,
                ),
              ),
            ),
          );
        }

        // Date section header — no animation stagger
        if (item is String) {
          tileIndex = 0; // reset stagger counter at each date boundary
          return _DateSectionHeader(label: item);
        }

        // Activity tile with entrance animation
        final activity = item as GroupActivityLog;
        final delay = Duration(milliseconds: (tileIndex % 10) * 50);
        tileIndex++;

        return GroupActivityTile(activity: activity)
            .animate()
            .fadeIn(delay: delay)
            .slideY(begin: 0.1, curve: Curves.easeOutCubic);
      },
    );
  }

  /// Skeleton placeholder rows shown while the first page loads.
  Widget _buildSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: 5,
      itemBuilder: (context, index) => const _SkeletonRow(),
    );
  }
}

/// Section header for date groups in the activity timeline (D-08).
class _DateSectionHeader extends StatelessWidget {
  final String label;

  const _DateSectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColorTokens.light.textMuted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// A skeleton placeholder tile shown during first-page loading.
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColorTokens.light.cardSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColorTokens.light.border,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 12,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColorTokens.light.border,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 10,
                  width: 80,
                  decoration: BoxDecoration(
                    color: AppColorTokens.light.inputFill,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
