import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/providers/connectivity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../events/models/event_model.dart';
import '../../groups/models/group_model.dart';
import '../keys/memories_keys.dart';
import '../models/memory_model.dart';
import '../providers/memory_provider.dart';
import '../widgets/full_screen_photo.dart';
import '../widgets/photo_grid.dart';

/// Memories screen - Photo timeline for a trip
class MemoriesScreen extends ConsumerStatefulWidget {
  final Event event;
  final Group group;

  const MemoriesScreen({super.key, required this.event, required this.group});

  @override
  ConsumerState<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends ConsumerState<MemoriesScreen> {
  bool _isUploading = false;

  Future<void> _addPhoto(ImageSource source) async {
    setState(() => _isUploading = true);

    final service = ref.read(memoryServiceProvider);
    final memory = await service.uploadPhoto(
      groupId: widget.event.groupId,
      eventId: widget.event.id,
      source: source,
    );

    if (!mounted) return;
    setState(() => _isUploading = false);

    if (memory != null) {
      ref.invalidate(
        eventMemoriesProvider(
          (groupId: widget.event.groupId, eventId: widget.event.id),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo added to memories!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  void _showSourcePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Add a Memory',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildSourceOption(
                    icon: Iconsax.camera,
                    label: 'Camera',
                    color: AppColors.primary,
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
                    color: AppColors.sky,
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
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.textMuted,
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
          borderRadius: BorderRadius.circular(20),
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
                fontWeight: FontWeight.w700,
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
    final memoriesAsync = ref.watch(
      eventMemoriesProvider(
        (groupId: widget.event.groupId, eventId: widget.event.id),
      ),
    );

    final connectivity = ref.watch(connectivityProvider);
    if (connectivity == ConnectivityStatus.offline) {
      return Scaffold(
        key: MemoriesKeys.screen,
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              const Expanded(
                child: EmptyStateView(
                  icon: Icons.cloud_off_rounded,
                  title: 'Unavailable Offline',
                  message:
                      'Memories require an internet connection.\nYour other trip data is available offline.',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      key: MemoriesKeys.screen,
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton(
        onPressed: _isUploading ? null : _showSourcePicker,
        backgroundColor: AppColors.primary,
        child: _isUploading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.black,
                  strokeWidth: 2.5,
                ),
              )
            : const Icon(Iconsax.camera, color: Colors.black),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context)
                .animate()
                .fadeIn()
                .slideY(begin: -0.2),

            Expanded(
              child: memoriesAsync.when(
                data: (memories) => memories.isEmpty
                    ? _buildEmptyState()
                    : MemoriesPhotoGrid(
                        memories: memories,
                        onTap: _showFullScreen,
                        onRefresh: () async {
                          ref.invalidate(
                            eventMemoriesProvider(
                              (groupId: widget.event.groupId, eventId: widget.event.id),
                            ),
                          );
                        },
                      ),
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Iconsax.gallery_slash,
                          size: 48, color: AppColors.textMuted),
                      const SizedBox(height: 16),
                      const Text(
                        'Could not load memories',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => ref.invalidate(
                          eventMemoriesProvider(
                            (groupId: widget.event.groupId, eventId: widget.event.id,),
                          ),
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Iconsax.arrow_left, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Memories',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Iconsax.camera, size: 14, color: AppColors.amber),
                const SizedBox(width: 6),
                Consumer(
                  builder: (context, ref, _) {
                    final count = ref
                            .watch(eventMemoriesProvider((groupId: widget.event.groupId, eventId: widget.event.id,)))
                            .valueOrNull
                            ?.length ??
                        0;
                    return Text(
                      '$count',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.amber,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Iconsax.camera,
                size: 52,
                color: AppColors.amber,
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'No memories yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Capture moments from your journey. Photos are shared with everyone on this trip.',
              style: TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _showSourcePicker,
              icon: const Icon(Iconsax.camera, size: 20),
              label: const Text('Add First Photo'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ).animate().fadeIn(duration: 600.ms),
      ),
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
                  groupId: widget.event.groupId,
                  eventId: widget.event.id,
                  memoryId: memory.id,
                  storagePath: memory.storagePath,
                );
                if (deleted) {
                  ref.invalidate(
                    eventMemoriesProvider(
                      (groupId: widget.event.groupId, eventId: widget.event.id,),
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
