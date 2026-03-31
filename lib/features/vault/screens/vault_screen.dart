import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/connectivity_provider.dart';
import '../../../shared/animations/fade_in_list.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/module_header.dart';
import '../../../shared/widgets/search_filter_bar.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../events/providers/event_provider.dart';
import '../keys/vault_keys.dart';
import '../models/document_model.dart';
import '../providers/document_provider.dart';
import '../widgets/vault_hero_card.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';

/// Vault Screen — unified module template (D-08, D-14, D-20).
///
/// Layout: dark ModuleHeader → VaultHeroCard → SearchFilterBar →
/// section overline → FadeInList of document cards.
/// Loading: SkeletonLoader. Empty: EmptyStateView with warm bronze gradient.
class VaultScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String eventId;

  const VaultScreen({
    super.key,
    required this.groupId,
    required this.eventId,
  });

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final eventRef = (groupId: widget.groupId, eventId: widget.eventId);
    final eventAsync = ref.watch(eventDetailProvider(eventRef));
    final documentsAsync = ref.watch(eventDocumentsProvider(eventRef));
    final isUploading = ref.watch(documentLoadingProvider);
    final connectivity = ref.watch(connectivityProvider);

    // Loading state — use skeleton instead of spinner
    if (eventAsync.isLoading) {
      return Scaffold(
        backgroundColor: AppColorTokens.light.scaffoldBackground,
        body: Column(
          children: [
            const ModuleHeader(title: 'Vault', useDarkTheme: true),
            Expanded(child: SkeletonLoader.documentList()),
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
            const ModuleHeader(title: 'Not Found', useDarkTheme: true),
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

    // Offline state — documents require connectivity
    if (connectivity == ConnectivityStatus.offline) {
      return Scaffold(
        key: VaultKeys.screen,
        backgroundColor: AppColorTokens.light.scaffoldBackground,
        body: Column(
          children: [
            ModuleHeader(
              title: 'Vault',
              subtitle: event.name.toUpperCase(),
              useDarkTheme: true,
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
      key: VaultKeys.screen,
      backgroundColor: AppColorTokens.light.scaffoldBackground,
      body: Column(
        children: [
          ModuleHeader(
            title: 'Vault',
            subtitle: event.name.toUpperCase(),
            useDarkTheme: true,
          ),
          Expanded(
            child: documentsAsync.when(
              data: (docs) => _buildContent(context, docs, isUploading),
              loading: SkeletonLoader.documentList,
              error: (e, _) => EmptyStateView(
                icon: Iconsax.warning_2,
                title: "Couldn't load Vault",
                message: 'Check your connection and try again.',
                actionLabel: 'Reload',
                onAction: () => ref.invalidate(
                  eventDocumentsProvider(
                    (groupId: widget.groupId, eventId: widget.eventId),
                  ),
                ),
                iconColor: AppColorTokens.light.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<Document> docs,
    bool isUploading,
  ) {
    final totalBytes =
        docs.fold<int>(0, (sum, doc) => sum + (doc.fileSize ?? 0));
    final totalSize = _formatTotalSize(totalBytes);

    final filteredDocs = docs.where((doc) {
      if (_searchQuery.isNotEmpty) {
        return doc.fileName.toLowerCase().contains(_searchQuery.toLowerCase());
      }
      return true;
    }).toList();

    return CustomScrollView(
      slivers: [
        // Hero card
        SliverToBoxAdapter(
          child: VaultHeroCard(
            fileCount: docs.length,
            totalSize: totalSize,
            onUpload: isUploading ? () {} : () => _uploadDocument(context),
          ),
        ),
        // Search filter bar
        SliverToBoxAdapter(
          child: SearchFilterBar(
            onSearchChanged: (q) => setState(() => _searchQuery = q),
            hintText: 'Search documents...',
          ),
        ),
        if (docs.isEmpty)
          SliverFillRemaining(
            child: EmptyStateView(
              icon: Iconsax.document,
              title: 'No documents yet',
              message:
                  'Upload tickets, booking confirmations, or any trip files.',
              actionLabel: 'Upload Document',
              onAction: () => _uploadDocument(context),
              accentGradient: const LinearGradient(
                colors: [Color(0xFF8B7355), Color(0xFFA89372)],
              ),
            ),
          )
        else ...[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              4,
            ),
            sliver: SliverToBoxAdapter(
              child: Text(
                'FILES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: AppColorTokens.light.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              16,
              0,
              16,
              32,
            ),
            sliver: SliverToBoxAdapter(
              child: FadeInList(
                children: filteredDocs.map((doc) {
                  return Padding(
                    padding:
                        const EdgeInsets.only(bottom: 8),
                    child: _buildDocumentCard(context, doc),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDocumentCard(BuildContext context, Document doc) {
    return Container(
      decoration: BoxDecoration(
        color: AppColorTokens.light.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColorTokens.light.inputFill, width: 1.5),
        boxShadow: AppShadowTokens.standard.raised,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Dismissible(
          key: Key(doc.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            color: AppColorTokens.light.error.withValues(alpha: 0.1),
            child: Icon(Iconsax.trash, color: AppColorTokens.light.errorText),
          ),
          confirmDismiss: (direction) async {
            return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: AppColorTokens.light.cardSurface,
                title: const Text(
                  'DELETE FILE',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16),
                ),
                content: const Text(
                  'Delete this document? It will be permanently removed.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(
                      'Delete',
                      style: TextStyle(color: AppColorTokens.light.errorText),
                    ),
                  ),
                ],
              ),
            );
          },
          onDismissed: (_) => _deleteDocument(doc),
          child: InkWell(
            onTap: () => _openDocument(context, doc),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Icon container — 52dp, moduleVaultLight bg (D-20)
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColorTokens.light.moduleVaultLight,
                      borderRadius: BorderRadius.circular(
                          12),
                    ),
                    child: Icon(
                      _getTypeIcon(doc.type),
                      color: AppColorTokens.light.moduleVault,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.fileName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColorTokens.light.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _buildMetadata(doc),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: AppColorTokens.light.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                      color: AppColorTokens.light.inputFill,
                      borderRadius:
                          BorderRadius.circular(8),
                    ),
                    child: Text(
                      doc.extension.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColorTokens.light.textSecondary,
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

  String _buildMetadata(Document doc) {
    final parts = <String>[];
    parts.add(doc.formattedSize);
    if (doc.createdAt != null) {
      final d = doc.createdAt!;
      parts.add('${d.day}/${d.month}/${d.year}');
    }
    if (doc.uploaderName != null) {
      parts.add(doc.uploaderName!);
    }
    return parts.join(' · ');
  }

  String _formatTotalSize(int bytes) {
    if (bytes == 0) return '0 KB';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  IconData _getTypeIcon(DocumentType type) {
    return switch (type) {
      DocumentType.image => Iconsax.image,
      DocumentType.pdf => Iconsax.document_text,
      DocumentType.document => Iconsax.document_1,
      DocumentType.spreadsheet => Iconsax.chart_1,
      DocumentType.other => Iconsax.document,
    };
  }

  Future<void> _deleteDocument(Document doc) async {
    final service = ref.read(documentServiceProvider);
    await service.deleteDocument(
      groupId: widget.groupId,
      eventId: widget.eventId,
      documentId: doc.id,
      storagePath: doc.fileUrl,
    );
  }

  void _uploadDocument(BuildContext context) async {
    final service = ref.read(documentServiceProvider);
    final result = await service.pickAndUpload(
      groupId: widget.groupId,
      eventId: widget.eventId,
    );

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
          backgroundColor: AppColorTokens.light.primary,
        ),
      );
    } else {
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
            backgroundColor: AppColorTokens.light.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _openDocument(BuildContext context, Document doc) async {
    try {
      final service = ref.read(documentServiceProvider);
      final url = await service.getDownloadUrl(doc.fileUrl);
      if (url == null) throw Exception('Could not generate access link');

      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not open file: $e'),
          backgroundColor: AppColorTokens.light.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }
}
