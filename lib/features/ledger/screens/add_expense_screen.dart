import 'dart:io';
import 'package:decimal/decimal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/haptic_service.dart';
import '../../logistics/models/sub_group_model.dart';
import '../../logistics/providers/sub_group_provider.dart';
import '../../trip/providers/trip_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/expense_category_model.dart';
import '../models/expense_model.dart';
import '../providers/category_provider.dart';
import '../providers/expense_provider.dart';

/// Omni-Splitter (Add Expense Screen) - Redesigned with 3-step flow
class AddExpenseScreen extends ConsumerStatefulWidget {
  final String tripId;

  const AddExpenseScreen({super.key, required this.tripId});

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _noteController = TextEditingController();

  // Custom numeric entry state
  String _amount = '0';
  int _currentStep = 0; // 0: Amount, 1: Classify, 2: Split/Confirm

  ExpenseScope _scope = ExpenseScope.global;
  String? _selectedCategoryId;
  String? _selectedSubGroupId;
  final Set<String> _customSplitParticipants = {};

  // Leader can add expense on behalf of others
  String? _selectedPayerId;

  // Receipt capture state
  String? _receiptPath;
  bool _isUploadingReceipt = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  /// Find and auto-select the user's current car sub-group
  void _autoSelectUserSubGroup() {
    final currentParticipant = ref.read(
      currentParticipantProvider(widget.tripId),
    );
    if (currentParticipant == null) return;

    final subGroupsAsync = ref.read(tripSubGroupsProvider(widget.tripId));
    final subGroups = subGroupsAsync.valueOrNull ?? [];

    // Find the first car sub-group the user is a member of
    for (final sg in subGroups) {
      if (sg.type == SubGroupType.car) {
        final isMember = sg.members.any(
          (m) => m.participantId == currentParticipant.id,
        );
        if (isMember) {
          setState(() => _selectedSubGroupId = sg.id);
          return;
        }
      }
    }

    // If no car assignment found, just use the first available car
    final firstCar = subGroups
        .where((sg) => sg.type == SubGroupType.car)
        .firstOrNull;
    if (firstCar != null) {
      setState(() => _selectedSubGroupId = firstCar.id);
    }
  }

  void _onKeyPress(String key) {
    HapticService.lightClick();
    setState(() {
      if (key == 'back') {
        if (_amount.length > 1) {
          _amount = _amount.substring(0, _amount.length - 1);
        } else {
          _amount = '0';
        }
      } else if (key == '.') {
        if (!_amount.contains('.')) {
          _amount += '.';
        }
      } else {
        if (_amount == '0') {
          _amount = key;
        } else {
          // Limit to 3 decimal places (OMR)
          if (_amount.contains('.')) {
            final parts = _amount.split('.');
            if (parts[1].length < 3) {
              _amount += key;
            }
          } else {
            _amount += key;
          }
        }
      }
    });
  }

  Future<void> _submit() async {
    final amount = Decimal.parse(_amount);
    final note = _noteController.text.trim();

    final currentParticipant = ref.read(
      currentParticipantProvider(widget.tripId),
    );
    if (currentParticipant == null) {
      ref.read(expenseErrorProvider.notifier).state =
          'Could not identify your participant record.';
      return;
    }

    // Upload receipt if one was selected
    String? receiptUrl;
    if (_receiptPath != null) {
      setState(() => _isUploadingReceipt = true);
      receiptUrl = await _uploadReceipt(_receiptPath!);
      setState(() => _isUploadingReceipt = false);
    }

    final expenseService = ref.read(expenseServiceProvider);
    final expense = await expenseService.addExpense(
      tripId: widget.tripId,
      payerParticipantId: _selectedPayerId ?? currentParticipant.id,
      amount: amount,
      description: note.isNotEmpty ? note : null,
      scope: _scope,
      subGroupId: _selectedSubGroupId,
      customSplitParticipants: _scope == ExpenseScope.custom
          ? _customSplitParticipants.toList()
          : null,
      receiptUrl: receiptUrl,
      categoryId: _selectedCategoryId,
    );

    if (expense != null && mounted) {
      _showSuccessDialog(expense);
    }
  }

  /// Pick a receipt image from gallery or camera
  Future<void> _pickReceipt() async {
    HapticService.lightClick();

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null &&
        result.files.isNotEmpty &&
        result.files.first.path != null) {
      setState(() {
        _receiptPath = result.files.first.path;
      });
    }
  }

  /// Upload receipt to Supabase Storage
  Future<String?> _uploadReceipt(String filePath) async {
    try {
      final file = File(filePath);
      final fileName = filePath.split('/').last;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath = '${widget.tripId}/receipts/$timestamp-$fileName';

      await SupabaseConfig.client.storage
          .from('trip-documents')
          .upload(storagePath, file);

      final url = SupabaseConfig.client.storage
          .from('trip-documents')
          .getPublicUrl(storagePath);

      return url;
    } catch (e) {
      debugPrint('Receipt upload failed: $e');
      return null;
    }
  }

  void _showSuccessDialog(Expense expense) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SuccessDialog(
        expense: expense,
        onDone: () {
          Navigator.of(context).pop();
          context.pop(true);
        },
        onAddAnother: () {
          Navigator.of(context).pop();
          setState(() {
            _amount = '0';
            _currentStep = 0;
            _noteController.clear();
          });
        },
      ),
    );
  }

  void _nextStep() {
    if (_currentStep == 0 && (Decimal.parse(_amount) <= Decimal.zero)) return;
    HapticService.medium();
    setState(() => _currentStep++);
  }

  void _prevStep() {
    HapticService.lightClick();
    setState(() => _currentStep--);
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(expenseLoadingProvider);
    final error = ref.watch(expenseErrorProvider);
    final categoriesAsync = ref.watch(tripCategoriesProvider(widget.tripId));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildStepHeader(),
            Expanded(
              child: IndexedStack(
                index: _currentStep,
                children: [
                  _buildAmountStep(),
                  _buildCategoryStep(categoriesAsync),
                  _buildConfirmStep(error),
                ],
              ),
            ),
            _buildBottomAction(isLoading),
          ],
        ),
      ),
    );
  }

  Widget _buildStepHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(
                  _currentStep == 0 ? Icons.close : Iconsax.arrow_left,
                  color: AppColors.textSecondary,
                ),
                onPressed: () =>
                    _currentStep == 0 ? context.pop() : _prevStep(),
              ),
              Text(
                [
                  'ENTER AMOUNT',
                  'SELECT CATEGORY',
                  'SPLIT & CONFIRM',
                ][_currentStep],
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 48), // Placeholder for balance
            ],
          ),
          const SizedBox(height: 8),
          // Progress Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: List.generate(3, (index) {
                return Expanded(
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: index <= _currentStep
                          ? AppColors.mint
                          : AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        // Amount Display
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Text(
              'OMR',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w300,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _amount,
              style: const TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const Spacer(),
        // Numpad
        _buildNumpad(),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildNumpad() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          _buildNumpadRow(['1', '2', '3']),
          const SizedBox(height: 20),
          _buildNumpadRow(['4', '5', '6']),
          const SizedBox(height: 20),
          _buildNumpadRow(['7', '8', '9']),
          const SizedBox(height: 20),
          _buildNumpadRow(['.', '0', 'back']),
        ],
      ),
    );
  }

  Widget _buildNumpadRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: keys.map((key) {
        if (key == 'back') {
          return _buildNumpadKey(
            child: const Icon(
              Icons.backspace_outlined,
              color: AppColors.textPrimary,
            ),
            onTap: () => _onKeyPress('back'),
          );
        }
        return _buildNumpadKey(
          child: Text(
            key,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          onTap: () => _onKeyPress(key),
        );
      }).toList(),
    );
  }

  Widget _buildNumpadKey({required Widget child, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 80,
        height: 60,
        alignment: Alignment.center,
        child: child,
      ),
    );
  }

  Widget _buildCategoryStep(AsyncValue<List<ExpenseCategory>> categoriesAsync) {
    return categoriesAsync.when(
      data: (categories) => Column(
        children: [
          const SizedBox(height: 44),
          const Text(
            'What was this for?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 44),
          SizedBox(
            height: 120,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (context, index) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final cat = categories[index];
                final isSelected = _selectedCategoryId == cat.id;
                return GestureDetector(
                  onTap: () {
                    HapticService.lightClick();
                    setState(() => _selectedCategoryId = cat.id);
                  },
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.mint
                              : AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppColors.mint.withValues(alpha: 0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          cat.iconData,
                          color: isSelected
                              ? Colors.white
                              : AppColors.textSecondary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        cat.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isSelected
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildConfirmStep(String? error) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Split Details',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 24),
          // Scope Tabs
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _buildConfirmScopeTab(
                      'Global',
                      ExpenseScope.global,
                      Iconsax.global,
                    ),
                    _buildConfirmScopeTab(
                      'My Car',
                      ExpenseScope.subGroup,
                      Iconsax.car,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildConfirmScopeTab(
                      'Custom',
                      ExpenseScope.custom,
                      Iconsax.people,
                    ),
                    _buildConfirmScopeTab(
                      'Personal',
                      ExpenseScope.personal,
                      Iconsax.user,
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Custom participant selection
          if (_scope == ExpenseScope.custom) ...[
            const SizedBox(height: 16),
            _buildCustomParticipantSelector(),
          ],
          const SizedBox(height: 24),
          // Paid By selector (for leaders only)
          _buildPayerSelector(),
          const SizedBox(height: 24),
          // Note Input
          const Text(
            'NOTE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: AppColors.textMuted,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'e.g. Lunch at trailhead...',
              fillColor: AppColors.surfaceLight,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          // Receipt Capture
          const SizedBox(height: 24),
          const Text(
            'RECEIPT (OPTIONAL)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: AppColors.textMuted,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _pickReceipt,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _receiptPath != null
                      ? AppColors.mint
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: _receiptPath != null
                  ? Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(_receiptPath!),
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Receipt attached',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                'Tap to change',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            HapticService.lightClick();
                            setState(() => _receiptPath = null);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.rose.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Iconsax.trash,
                              size: 18,
                              color: AppColors.rose,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Iconsax.camera,
                            size: 20,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Add a receipt photo',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          if (_isUploadingReceipt)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Uploading receipt...'),
                ],
              ),
            ),
          if (error != null) _buildErrorBanner(error),
        ],
      ),
    );
  }

  Widget _buildConfirmScopeTab(
    String label,
    ExpenseScope scope,
    IconData icon,
  ) {
    final isSelected = _scope == scope;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticService.selection();
          setState(() => _scope = scope);

          // Auto-select user's sub-group when choosing 'My Car' scope
          if (scope == ExpenseScope.subGroup) {
            _autoSelectUserSubGroup();
          } else {
            _selectedSubGroupId = null;
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected ? AppColors.cardShadow : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? AppColors.mint : AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? AppColors.textPrimary
                      : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build participant multi-select for custom splits
  Widget _buildCustomParticipantSelector() {
    final participantsAsync = ref.watch(
      tripLogisticsParticipantsProvider(widget.tripId),
    );
    final currentParticipant = ref.watch(
      currentParticipantProvider(widget.tripId),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'SELECT PARTICIPANTS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: AppColors.textMuted,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              '${_customSplitParticipants.length} selected',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _customSplitParticipants.isNotEmpty
                    ? AppColors.mint
                    : AppColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(16),
          ),
          constraints: const BoxConstraints(maxHeight: 200),
          child: participantsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
            data: (participants) {
              // Exclude current user from selection (they're auto-included)
              final otherParticipants = participants
                  .where((p) => p.id != currentParticipant?.id)
                  .toList();

              if (otherParticipants.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No other participants to select'),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                itemCount: otherParticipants.length,
                itemBuilder: (context, index) {
                  final participant = otherParticipants[index];
                  final isSelected = _customSplitParticipants.contains(
                    participant.id,
                  );

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.mint.withValues(alpha: 0.2)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          (participant.displayName ?? 'U')[0].toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? AppColors.mint
                                : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      participant.displayName ?? 'Unknown',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    subtitle: participant.isShadow
                        ? Text(
                            'Shadow Profile',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          )
                        : null,
                    trailing: Checkbox(
                      value: isSelected,
                      activeColor: AppColors.mint,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      onChanged: (checked) {
                        HapticService.lightClick();
                        setState(() {
                          if (checked == true) {
                            _customSplitParticipants.add(participant.id);
                          } else {
                            _customSplitParticipants.remove(participant.id);
                          }
                        });
                      },
                    ),
                    onTap: () {
                      HapticService.lightClick();
                      setState(() {
                        if (isSelected) {
                          _customSplitParticipants.remove(participant.id);
                        } else {
                          _customSplitParticipants.add(participant.id);
                        }
                      });
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Build payer selector (leaders can add expense on behalf of others)
  Widget _buildPayerSelector() {
    final currentParticipant = ref.watch(
      currentParticipantProvider(widget.tripId),
    );
    final trip = ref
        .watch(userTripsProvider)
        .valueOrNull
        ?.firstWhere(
          (t) => t.id == widget.tripId,
          orElse: () => throw Exception('Trip not found'),
        );
    final participantsAsync = ref.watch(
      tripLogisticsParticipantsProvider(widget.tripId),
    );
    final participants = participantsAsync.valueOrNull ?? [];

    // Check if current user is the leader
    final isLeader = trip?.leaderId == ref.watch(currentUserProvider)?.id;

    // If not leader or no participants, don't show
    if (!isLeader || participants.isEmpty) {
      return const SizedBox.shrink();
    }

    // Default to current participant if not set
    final effectivePayerId = _selectedPayerId ?? currentParticipant?.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PAID BY',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: AppColors.textMuted,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.3)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: effectivePayerId,
              isExpanded: true,
              icon: const Icon(Iconsax.arrow_down_1),
              items: participants.map((p) {
                final isMe = p.id == currentParticipant?.id;
                return DropdownMenuItem(
                  value: p.id,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.primaryLight,
                        child: Text(
                          (p.displayName ?? 'U')[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isMe
                              ? '${p.displayName ?? 'Unknown'} (Me)'
                              : p.displayName ?? 'Unknown',
                          style: TextStyle(
                            fontWeight: isMe
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                HapticService.lightClick();
                setState(() => _selectedPayerId = value);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner(String error) {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.rose.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Iconsax.warning_2, color: AppColors.rose, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(color: AppColors.rose, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomAction(bool isLoading) {
    final isLastStep = _currentStep == 2;
    final amountValue = Decimal.tryParse(_amount) ?? Decimal.zero;
    final canContinue = amountValue > Decimal.zero;

    return Container(
      padding: const EdgeInsets.all(24),
      child: SizedBox(
        width: double.infinity,
        height: 64,
        child: Container(
          decoration: BoxDecoration(
            gradient: isLastStep ? AppColors.primaryGradient : null,
            color: isLastStep
                ? null
                : (canContinue
                      ? AppColors.textPrimary
                      : AppColors.surfaceLight),
            borderRadius: BorderRadius.circular(20),
            boxShadow: canContinue
                ? [
                    BoxShadow(
                      color:
                          (isLastStep
                                  ? AppColors.primary
                                  : AppColors.textPrimary)
                              .withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: ElevatedButton(
            onPressed: isLoading
                ? null
                : (canContinue ? (isLastStep ? _submit : _nextStep) : null),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        isLastStep ? 'CONFIRM & LOG' : 'NEXT STEP',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Iconsax.arrow_right_1, color: Colors.white),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Success Dialog after saving expense
class _SuccessDialog extends StatelessWidget {
  final Expense expense;
  final VoidCallback onDone;
  final VoidCallback onAddAnother;

  const _SuccessDialog({
    required this.expense,
    required this.onDone,
    required this.onAddAnother,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Close button
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: AppColors.textMuted),
                onPressed: onDone,
              ),
            ),

            // Success Icon
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Iconsax.tick_circle5,
                size: 48,
                color: AppColors.primary,
              ),
            ).animate().scale(
              delay: 100.ms,
              duration: 300.ms,
              curve: Curves.elasticOut,
            ),

            const SizedBox(height: 16),

            Text(
              'Expense Saved',
              style: Theme.of(context).textTheme.headlineSmall,
            ),

            const SizedBox(height: 4),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'SYNCED TO CLOUD',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Summary Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppColors.cardShadow,
              ),
              child: Column(
                children: [
                  Text(
                    'TOTAL AMOUNT',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    expense.formattedAmount,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Category row
                  if (expense.categoryName != null)
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Iconsax.category,
                            size: 18,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CATEGORY',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            Text(
                              expense.categoryName!,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        const Icon(
                          Iconsax.arrow_right_3,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                      ],
                    ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Done Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: onDone,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Done', style: TextStyle(fontWeight: FontWeight.w600)),
                    SizedBox(width: 8),
                    Icon(Iconsax.tick_circle, size: 18),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Add Another
            TextButton(
              onPressed: onAddAnother,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Iconsax.add, size: 18),
                  SizedBox(width: 8),
                  Text('Add Another'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
