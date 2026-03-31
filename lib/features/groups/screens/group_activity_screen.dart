import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../shared/widgets/empty_state_view.dart';
import '../keys/group_keys.dart';
import '../models/group_activity_log_model.dart';
import '../providers/group_balance_provider.dart';
import '../widgets/group_activity_tile.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';

/// Full-screen paginated group activity log (GRP-05).
///
/// Uses cursor-based pagination via [GroupActivityService.fetchActivityPageRaw].
/// Loads 50 entries per page. Shows a "Load more" button when [_hasMore] is true.
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

  @override
  void initState() {
    super.initState();
    _loadPage();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: GroupKeys.activityScreen,
      backgroundColor: AppColorTokens.light.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColorTokens.light.cardSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColorTokens.light.inputFill, width: 1),
              boxShadow: AppShadowTokens.standard.raised,
            ),
            child: IconButton(
              key: GroupKeys.activityBackButton,
              icon: const Icon(Iconsax.arrow_left, size: 20),
              onPressed: () => Navigator.pop(context),
              tooltip: 'Back',
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          Text(
            key: GroupKeys.activityScreenTitle,
            'Group Activity',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: AppColorTokens.light.textPrimary,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    // Loading first page
    if (_isLoadingMore && _activities.isEmpty) {
      return _buildSkeleton();
    }

    // Empty state
    if (_activities.isEmpty) {
      return const EmptyStateView(
        icon: Iconsax.activity,
        title: 'No group activity yet',
        message:
            'Actions like creating events and settling up will appear here.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      itemCount: _activities.length + (_hasMore ? 1 : 0),
      separatorBuilder: (context, index) => Divider(
        height: 1,
        thickness: 1,
        color: AppColorTokens.light.border,
      ),
      itemBuilder: (context, index) {
        if (index == _activities.length) {
          // "Load more" row at the bottom
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: _isLoadingMore
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: TextButton(
                      onPressed: _loadPage,
                      child: Text(
                        'Load more',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColorTokens.light.primary,
                        ),
                      ),
                    ),
                  ),
          );
        }
        return GroupActivityTile(activity: _activities[index]);
      },
    );
  }

  /// Skeleton placeholder rows shown while the first page loads.
  Widget _buildSkeleton() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      itemCount: 5,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        thickness: 1,
        color: AppColorTokens.light.border,
      ),
      itemBuilder: (context, index) => const _SkeletonRow(),
    );
  }
}

/// A 52px skeleton placeholder for a single activity row.
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColorTokens.light.border,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
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
