import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';

import '../models/memory_model.dart';
import '../../../core/theme/tokens/color_tokens.dart';

/// Scrollable staggered photo grid grouped by date.
///
/// Each photo tile calls [onTap] when tapped so the parent can show the
/// full-screen viewer. [onRefresh] is called when the user pulls to refresh.
class MemoriesPhotoGrid extends StatelessWidget {
  final List<Memory> memories;
  final void Function(Memory memory) onTap;
  final Future<void> Function() onRefresh;

  const MemoriesPhotoGrid({
    super.key,
    required this.memories,
    required this.onTap,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Memory>>{};
    for (final memory in memories) {
      final dateKey = DateFormat('MMMM d, yyyy').format(memory.createdAt);
      grouped.putIfAbsent(dateKey, () => []).add(memory);
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColorTokens.light.primary,
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
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 4,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColorTokens.light.inputFill,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        dateKey,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColorTokens.light.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${photos.length} photo${photos.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColorTokens.light.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              _buildStaggeredGrid(photos),
            ],
          )
              .animate()
              .fadeIn(delay: Duration(milliseconds: sectionIndex * 100));
        },
      ),
    );
  }

  Widget _buildStaggeredGrid(List<Memory> photos) {
    final rows = <Widget>[];

    for (var i = 0; i < photos.length; i += 3) {
      if (i + 2 < photos.length) {
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
      onTap: () => onTap(memory),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AppColorTokens.light.inputFill,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (memory.signedUrl != null)
              CachedNetworkImage(
                imageUrl: memory.signedUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: AppColorTokens.light.inputFill,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColorTokens.light.textMuted,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: AppColorTokens.light.inputFill,
                  child: Icon(
                    Iconsax.gallery_slash,
                    color: AppColorTokens.light.textMuted,
                  ),
                ),
              )
            else
              Center(
                child: Icon(Iconsax.gallery_slash, color: AppColorTokens.light.textMuted),
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
}
