import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/connectivity_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/module_header.dart';
import '../../../shared/widgets/search_filter_bar.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../trip/models/trip_model.dart';
import '../models/document_model.dart';
import '../providers/document_provider.dart';

/// Vault Screen - Document management with upload/download
class VaultScreen extends ConsumerStatefulWidget {
  final Trip trip;

  const VaultScreen({super.key, required this.trip});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final documentsAsync = ref.watch(tripDocumentsProvider(widget.trip.id));
    final isLoading = ref.watch(documentLoadingProvider);
    final connectivity = ref.watch(connectivityProvider);

    if (connectivity == ConnectivityStatus.offline) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            ModuleHeader(
              title: 'Vault',
              subtitle: widget.trip.name.toUpperCase(),
            ),
            const Expanded(
              child: EmptyStateView(
                icon: Icons.cloud_off_rounded,
                title: 'Unavailable Offline',
                message:
                    'Documents require an internet connection.\nYour other trip data is available offline.',
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          ModuleHeader(
            title: 'Vault',
            subtitle: widget.trip.name.toUpperCase(),
            actions: [
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(AppColors.radiusSmall + 2),
                  border: Border.all(color: AppColors.border),
                ),
                child: const IconButton(
                  icon: Icon(
                    Iconsax.lock,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  onPressed: null,
                ),
              ),
            ],
          ),
          SearchFilterBar(
            onSearchChanged: (q) => setState(() => _searchQuery = q),
            hintText: 'Search documents...',
          ),
          const SizedBox(height: 12),
          Expanded(
            child: documentsAsync.when(
              data: (docs) => docs.isEmpty
                  ? _buildEmptyState(context, ref)
                  : _buildDocumentList(context, ref, docs),
              loading: () => SkeletonLoader.documentList(),
              error: (e, _) => _buildErrorState(context, e.toString()),
            ),
          ),
        ],
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

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return EmptyStateView(
      icon: Iconsax.document,
      title: 'No documents yet',
      message: 'Upload tickets, bookings, or any trip files',
      actionLabel: 'Upload',
      onAction: () => _uploadDocument(context, ref),
      iconColor: AppColors.indigo,
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
    final filteredDocs = docs.where((doc) {
      if (_searchQuery.isNotEmpty) {
        return doc.fileName.toLowerCase().contains(_searchQuery.toLowerCase());
      }
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(tripDocumentsProvider(widget.trip.id));
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: filteredDocs.length,
        itemBuilder: (context, index) {
          final doc = filteredDocs[index];
          return _buildDocumentItem(context, ref, doc, index)
              .animate()
              .fadeIn(delay: Duration(milliseconds: (50 * index).clamp(0, 500)), duration: 300.ms)
              .slideY(begin: 0.05, end: 0, delay: Duration(milliseconds: (50 * index).clamp(0, 500)));
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderLight, width: 1.5),
        boxShadow: AppColors.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Dismissible(
          key: Key(doc.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            color: AppColors.rose.withValues(alpha: 0.1),
            child: const Icon(Iconsax.trash, color: AppColors.rose),
          ),
          confirmDismiss: (direction) async {
            return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: AppColors.surface,
                title: const Text(
                  'DELETE FILE',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                content: Text(
                  'Permanently remove "${doc.fileName.toUpperCase()}"?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('KEEP'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text(
                      'DELETE',
                      style: TextStyle(
                        color: AppColors.rose,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
          onDismissed: (_) =>
              ref.read(documentServiceProvider).deleteDocument(doc),
          child: InkWell(
            onTap: () => _openDocument(context, ref, doc),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: _getTypeColor(doc.type).withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _getTypeColor(doc.type).withValues(alpha: 0.1),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      _getTypeIcon(doc.type),
                      color: _getTypeColor(doc.type),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.fileName.toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              doc.formattedSize,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (doc.uploaderName != null) ...[
                              Text(
                                ' • ',
                                style: TextStyle(color: AppColors.textMuted),
                              ),
                              Flexible(
                                child: Text(
                                  doc.uploaderName!.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w900,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      doc.extension.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
    final result = await service.pickAndUpload(tripId: widget.trip.id);

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
      // Get signed URL from service (cached if possible)
      final url = await ref
          .read(documentServiceProvider)
          .getSignedUrl(doc.fileUrl);
      if (url == null) throw Exception('Could not generate access link');

      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(
          content: Text('Could not open file: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }
}
