import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/connectivity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../trip/models/trip_model.dart';
import '../models/memory_model.dart';
import '../providers/memory_provider.dart';

/// Memories screen - Photo timeline for a trip
class MemoriesScreen extends ConsumerStatefulWidget {
  final Trip trip;

  const MemoriesScreen({super.key, required this.trip});

  @override
  ConsumerState<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends ConsumerState<MemoriesScreen> {
  bool _isUploading = false;

  Future<void> _addPhoto(ImageSource source) async {
    setState(() => _isUploading = true);

    final service = ref.read(memoryServiceProvider);
    final memory = await service.uploadPhoto(
      tripId: widget.trip.id,
      source: source,
    );

    if (!mounted) return;
    setState(() => _isUploading = false);

    if (memory != null) {
      ref.invalidate(tripMemoriesProvider(widget.trip.id));
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
    final memoriesAsync = ref.watch(tripMemoriesProvider(widget.trip.id));

    final connectivity = ref.watch(connectivityProvider);
    if (connectivity == ConnectivityStatus.offline) {
      return Scaffold(
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
            // Header
            _buildHeader(context)
                .animate()
                .fadeIn()
                .slideY(begin: -0.2),

            // Content
            Expanded(
              child: memoriesAsync.when(
                data: (memories) => memories.isEmpty
                    ? _buildEmptyState()
                    : _buildPhotoGrid(memories),
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
                      Text(
                        'Could not load memories',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => ref.invalidate(
                            tripMemoriesProvider(widget.trip.id)),
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
                            .watch(tripMemoriesProvider(widget.trip.id))
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
            Text(
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

  Widget _buildPhotoGrid(List<Memory> memories) {
    // Group by date
    final grouped = <String, List<Memory>>{};
    for (final memory in memories) {
      final dateKey = DateFormat('MMMM d, yyyy').format(memory.createdAt);
      grouped.putIfAbsent(dateKey, () => []).add(memory);
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(tripMemoriesProvider(widget.trip.id));
      },
      color: AppColors.primary,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: grouped.length,
        itemBuilder: (context, sectionIndex) {
          final dateKey = grouped.keys.elementAt(sectionIndex);
          final photos = grouped[dateKey]!;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date header
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        dateKey,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${photos.length} photo${photos.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              // Photo grid - staggered 2 columns
              _buildStaggeredGrid(photos, sectionIndex),
            ],
          )
              .animate()
              .fadeIn(delay: Duration(milliseconds: sectionIndex * 100));
        },
      ),
    );
  }

  Widget _buildStaggeredGrid(List<Memory> photos, int sectionIndex) {
    final rows = <Widget>[];

    for (var i = 0; i < photos.length; i += 3) {
      if (i + 2 < photos.length) {
        // Row of 3: one large left, two small right
        rows.add(
          SizedBox(
            height: 240,
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildPhotoTile(photos[i], 240),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: _buildPhotoTile(photos[i + 1], 118)),
                      const SizedBox(height: 4),
                      Expanded(child: _buildPhotoTile(photos[i + 2], 118)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (i + 1 < photos.length) {
        // Row of 2: equal width
        rows.add(
          SizedBox(
            height: 180,
            child: Row(
              children: [
                Expanded(child: _buildPhotoTile(photos[i], 180)),
                const SizedBox(width: 4),
                Expanded(child: _buildPhotoTile(photos[i + 1], 180)),
              ],
            ),
          ),
        );
      } else {
        // Single photo: full width
        rows.add(
          SizedBox(
            height: 220,
            child: _buildPhotoTile(photos[i], 220),
          ),
        );
      }
      rows.add(const SizedBox(height: 4));
    }

    return Column(children: rows);
  }

  Widget _buildPhotoTile(Memory memory, double height) {
    return GestureDetector(
      onTap: () => _showFullScreen(memory),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AppColors.surfaceLight,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (memory.signedUrl != null)
              CachedNetworkImage(
                imageUrl: memory.signedUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: AppColors.surfaceLight,
                  child: const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: AppColors.surfaceLight,
                  child: const Icon(
                    Iconsax.gallery_slash,
                    color: AppColors.textMuted,
                  ),
                ),
              )
            else
              const Center(
                child: Icon(Iconsax.gallery_slash, color: AppColors.textMuted),
              ),

            // Gradient overlay at bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.4),
                    ],
                  ),
                ),
              ),
            ),

            // Uploader name
            if (memory.uploaderName != null)
              Positioned(
                bottom: 8,
                left: 10,
                child: Text(
                  memory.uploaderName!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
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
            child: _FullScreenPhoto(
              memory: memory,
              onDelete: () async {
                Navigator.pop(context);
                final service = ref.read(memoryServiceProvider);
                final deleted = await service.deleteMemory(memory);
                if (deleted) {
                  ref.invalidate(tripMemoriesProvider(widget.trip.id));
                }
              },
            ),
          );
        },
      ),
    );
  }
}

/// Full screen photo viewer
class _FullScreenPhoto extends StatelessWidget {
  final Memory memory;
  final VoidCallback onDelete;

  const _FullScreenPhoto({
    required this.memory,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Stack(
          children: [
            // Photo
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: CachedNetworkImage(
                  imageUrl: memory.signedUrl!,
                  fit: BoxFit.contain,
                ),
              ),
            ),

            // Top bar
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Iconsax.close_circle,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const Spacer(),
                    if (memory.uploaderName != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          memory.uploaderName!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete Photo'),
                            content: const Text(
                              'Remove this photo from trip memories?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  onDelete();
                                },
                                child: const Text(
                                  'Delete',
                                  style: TextStyle(color: AppColors.error),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      icon: const Icon(
                        Iconsax.trash,
                        color: Colors.white70,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom info
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (memory.caption != null) ...[
                        Text(
                          memory.caption!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        DateFormat('MMMM d, yyyy  h:mm a')
                            .format(memory.createdAt),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13,
                        ),
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
}
