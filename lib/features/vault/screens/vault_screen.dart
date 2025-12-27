import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../trip/models/trip_model.dart';
import '../models/document_model.dart';
import '../providers/document_provider.dart';

/// Vault Screen - Document management with upload/download
class VaultScreen extends ConsumerWidget {
  final Trip trip;

  const VaultScreen({super.key, required this.trip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documentsAsync = ref.watch(tripDocumentsProvider(trip.id));
    final isLoading = ref.watch(documentLoadingProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: documentsAsync.when(
                data: (docs) => docs.isEmpty
                    ? _buildEmptyState(context, ref)
                    : _buildDocumentList(context, ref, docs),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _buildErrorState(context, e.toString()),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isLoading ? null : () => _uploadDocument(context, ref),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Iconsax.document_upload),
        label: Text(isLoading ? 'Uploading...' : 'Upload'),
      ).animate().fadeIn(delay: 300.ms).slideY(begin: 1),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Iconsax.arrow_left),
            onPressed: () => context.pop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vault',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(
                  '${trip.name} • Documents & Files',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.2);
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Icon(
                Iconsax.folder_open,
                size: 48,
                color: AppColors.primary,
              ),
            ).animate().fadeIn().scale(delay: 100.ms),

            const SizedBox(height: 24),

            Text(
              'No Documents Yet',
              style: Theme.of(context).textTheme.headlineMedium,
            ).animate().fadeIn(delay: 200.ms),

            const SizedBox(height: 8),

            Text(
              'Upload tickets, reservations, permits\nand other important files',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 300.ms),

            const SizedBox(height: 32),

            ElevatedButton.icon(
              onPressed: () => _uploadDocument(context, ref),
              icon: const Icon(Iconsax.add),
              label: const Text('Upload First File'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ).animate().fadeIn(delay: 400.ms),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Iconsax.warning_2, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text('Error loading documents'),
            const SizedBox(height: 8),
            Text(error, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentList(
    BuildContext context,
    WidgetRef ref,
    List<Document> docs,
  ) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(tripDocumentsProvider(trip.id));
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: docs.length,
        itemBuilder: (context, index) {
          final doc = docs[index];
          return _buildDocumentItem(context, ref, doc, index)
              .animate()
              .fadeIn(delay: Duration(milliseconds: 100 + (index * 50)))
              .slideX(begin: 0.1);
        },
      ),
    );
  }

  Widget _buildDocumentItem(
    BuildContext context,
    WidgetRef ref,
    Document doc,
    int index,
  ) {
    return Dismissible(
      key: Key(doc.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Iconsax.trash, color: AppColors.error),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Document'),
            content: Text('Delete "${doc.fileName}"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => ref.read(documentServiceProvider).deleteDocument(doc),
      child: GestureDetector(
        onTap: () => _openDocument(context, ref, doc),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppColors.cardShadow,
          ),
          child: Row(
            children: [
              // File type icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getTypeColor(doc.type).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getTypeIcon(doc.type),
                  color: _getTypeColor(doc.type),
                  size: 24,
                ),
              ),

              const SizedBox(width: 16),

              // File info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.fileName,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          doc.formattedSize,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (doc.uploaderName != null) ...[
                          const Text(' • '),
                          Text(
                            doc.uploaderName!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Extension badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  doc.extension,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Download button
              IconButton(
                tooltip: 'Download',
                icon: const Icon(Iconsax.document_download, size: 20),
                color: AppColors.primary,
                onPressed: () => _openDocument(context, ref, doc),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getTypeIcon(DocumentType type) {
    switch (type) {
      case DocumentType.image:
        return Iconsax.image;
      case DocumentType.pdf:
        return Iconsax.document_text;
      case DocumentType.document:
        return Iconsax.document_1;
      case DocumentType.spreadsheet:
        return Iconsax.chart_1;
      case DocumentType.other:
        return Iconsax.document;
    }
  }

  Color _getTypeColor(DocumentType type) {
    switch (type) {
      case DocumentType.image:
        return AppColors.info;
      case DocumentType.pdf:
        return AppColors.error;
      case DocumentType.document:
        return AppColors.primary;
      case DocumentType.spreadsheet:
        return AppColors.accentSecondary;
      case DocumentType.other:
        return AppColors.textSecondary;
    }
  }

  void _uploadDocument(BuildContext context, WidgetRef ref) async {
    final service = ref.read(documentServiceProvider);
    final result = await service.pickAndUpload(tripId: trip.id);

    if (!context.mounted) return;

    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Iconsax.tick_circle, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Text('${result.fileName} uploaded'),
            ],
          ),
          backgroundColor: AppColors.primary,
        ),
      );
    } else {
      // Check for error
      final error = ref.read(documentErrorProvider);
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Iconsax.warning_2, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text('Upload failed: $error')),
              ],
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _openDocument(BuildContext context, WidgetRef ref, Document doc) async {
    try {
      // Try to open the URL
      final uri = Uri.parse(doc.fileUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback to open_file
        await OpenFile.open(doc.fileUrl);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open file: $e')));
      }
    }
  }
}
