import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/module_header.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../events/providers/event_provider.dart';
import '../keys/memories_keys.dart';
import '../models/memory_model.dart';
import '../providers/memory_provider.dart';
import '../widgets/full_screen_photo.dart';
import '../widgets/memories_hero_card.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../shared/widgets/offline_banner.dart';

/// Memories screen — Photo timeline for an event.
///
/// Uses ModuleHeader (migrated from custom header per D-24 plan requirement).
/// Displays MemoriesHeroCard + 3-column photo grid with StaggeredGrid entrance.
///
/// IMPORTANT: _showFullScreen uses Navigator.push (not context.push) — this is
/// the only permitted Navigator.push in the codebase post-migration. It is an
/// overlay lightbox (opaque: false), not a navigation route per RESEARCH Pattern 5.
class MemoriesScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String eventId;

  const MemoriesScreen({
    super.key,
    required this.groupId,
    required this.eventId,
  });

  @override
  ConsumerState<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends ConsumerState<MemoriesScreen> {
  bool _isUploading = false;

  Future<void> _addPhoto(ImageSource source) async {
    setState(() => _isUploading = true);

    final service = ref.read(memoryServiceProvider);
    final memory = await service.uploadPhoto(
      groupId: widget.groupId,
      eventId: widget.eventId,
      source: source,
    );

    if (!mounted) return;
    setState(() => _isUploading = false);

    if (memory != null) {
      ref.invalidate(
        eventMemoriesProvider(
          (groupId: widget.groupId, eventId: widget.eventId),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Photo added to memories!'),
            backgroundColor: AppColorTokens.light.success,
          ),
        );
      }
    }
  }

  void _showSourcePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColorTokens.light.cardSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColorTokens.light.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Add a Memory',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColorTokens.light.textPrimary,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildSourceOption(
                    icon: Iconsax.camera,
                    label: 'Camera',
                    color: AppColorTokens.light.primary,
                    onTap: () {
                      Navigator.pop(context);
                      _addPhoto(ImageSource.camera);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildSourceOption(
                    icon: Iconsax.gallery,
                    label: 'Gallery',
                    color: AppColorTokens.light.primary,
                    onTap: () {
                      Navigator.pop(context);
                      _addPhoto(ImageSource.gallery);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: AppColorTokens.light.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eventRef = (groupId: widget.groupId, eventId: widget.eventId);
    final eventAsync = ref.watch(eventDetailProvider(eventRef));
    final memoriesAsync = ref.watch(eventMemoriesProvider(eventRef));

    // Loading state — skeleton while event loads
    if (eventAsync.isLoading) {
      return Scaffold(
        backgroundColor: AppColorTokens.light.scaffoldBackground,
        body: Column(
          children: [
            const ModuleHeader(
              title: 'Memories',
              useDarkTheme: true,
            ),
            Expanded(child: SkeletonLoader.photoGrid()),
          ],
        ),
      );
    }

    final event = eventAsync.valueOrNull;

    // Not-found state per D-11
    if (event == null) {
      return Scaffold(
        backgroundColor: AppColorTokens.light.scaffoldBackground,
        body: Column(
          children: [
            const ModuleHeader(title: 'Not Found'),
            Expanded(
              child: EmptyStateView(
                icon: Iconsax.warning_2,
                title: 'This event no longer exists',
                message:
                    'It may have been deleted. Tap below to go back to your groups.',
                actionLabel: 'Go Home',
                onAction: () => context.go('/home'),
                iconColor: AppColorTokens.light.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      key: MemoriesKeys.screen,
      backgroundColor: AppColorTokens.light.scaffoldBackground,
      body: memoriesAsync.when(
        loading: () => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: ModuleHeader(
                title: 'Memories',
                subtitle: event.name.toUpperCase(),
                useDarkTheme: true,
              ),
            ),
            SliverToBoxAdapter(
              child: SkeletonLoader.photoGrid(),
            ),
          ],
        ),
        error: (e, _) => Column(
          children: [
            ModuleHeader(
              title: 'Memories',
              subtitle: event.name.toUpperCase(),
              useDarkTheme: true,
            ),
            const OfflineBanner(),
            Expanded(
              child: EmptyStateView(
                icon: Iconsax.gallery_slash,
                title: "Couldn't load Memories",
                message: 'Check your connection and try again.',
                actionLabel: 'Reload',
                onAction: () => ref.invalidate(eventMemoriesProvider(eventRef)),
                iconColor: AppColorTokens.light.textSecondary,
              ),
            ),
          ],
        ),
        data: (memories) => Column(
          children: [
            ModuleHeader(
              title: 'Memories',
              subtitle: event.name.toUpperCase(),
              useDarkTheme: true,
            ),
            const OfflineBanner(),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  // 1. MemoriesHeroCard
                  SliverToBoxAdapter(
                    child: MemoriesHeroCard(
                      photoCount: memories.length,
                      dateRange: _buildDateRange(memories),
                      onAddPhoto: _isUploading ? () {} : _showSourcePicker,
                    ),
                  ),
                  // 2. Photo grid or empty state
                  if (memories.isEmpty)
                    SliverFillRemaining(
                      child: EmptyStateView(
                        icon: Iconsax.gallery,
                        title: 'No photos yet',
                        message:
                            'Add photos to capture the best moments of this trip.',
                        actionLabel: 'Add Photo',
                        onAction: _showSourcePicker,
                        accentGradient: LinearGradient(
                          colors: [AppColorTokens.light.moduleMemories, AppColorTokens.light.moduleMemoriesLight],
                        ),
                      ),
                    )
                  else
                    SliverToBoxAdapter(
                      child: _buildPhotoGrid(memories),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a pre-formatted date range string from the memories list.
  String _buildDateRange(List<Memory> memories) {
    if (memories.isEmpty) return '';
    final formatter = DateFormat('MMM d');
    final dates = memories.map((m) => m.createdAt).toList()..sort();
    final first = formatter.format(dates.first);
    final last = formatter.format(dates.last);
    return first == last ? first : '$first - $last';
  }

  Widget _buildPhotoGrid(List<Memory> memories) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: memories.length,
      itemBuilder: (context, index) {
        final memory = memories[index];
        return GestureDetector(
          onTap: () => _showFullScreen(memory),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: memory.signedUrl != null
                ? Image.network(
                    memory.signedUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: AppColorTokens.light.inputFill,
                      child: Icon(
                        Iconsax.gallery_slash,
                        color: AppColorTokens.light.textMuted,
                      ),
                    ),
                  )
                : Container(
                    color: AppColorTokens.light.inputFill,
                    child: Icon(
                      Iconsax.image,
                      color: AppColorTokens.light.textMuted,
                    ),
                  ),
          ),
        );
      },
    );
  }

  void _showFullScreen(Memory memory) {
    if (memory.signedUrl == null) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: FullScreenPhoto(
              memory: memory,
              onDelete: () async {
                Navigator.pop(context);
                final service = ref.read(memoryServiceProvider);
                final deleted = await service.deleteMemory(
                  groupId: widget.groupId,
                  eventId: widget.eventId,
                  memoryId: memory.id,
                  storagePath: memory.storagePath,
                );
                if (deleted) {
                  ref.invalidate(
                    eventMemoriesProvider(
                      (groupId: widget.groupId, eventId: widget.eventId),
                    ),
                  );
                }
              },
            ),
          );
        },
      ),
    );
  }
}
