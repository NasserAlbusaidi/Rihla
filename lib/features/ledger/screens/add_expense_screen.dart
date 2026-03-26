import 'dart:io';
import 'package:decimal/decimal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/haptic_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../logistics/models/sub_group_model.dart';
import '../../logistics/providers/sub_group_provider.dart';
import '../../trip/models/trip_model.dart';
import '../../trip/providers/trip_provider.dart';
import '../models/expense_model.dart';
import '../providers/category_provider.dart';
import '../providers/expense_provider.dart';
import '../widgets/amount_input_section.dart';
import '../widgets/category_selection_step.dart';
import '../widgets/expense_success_dialog.dart';
import '../widgets/receipt_picker_section.dart';
import '../widgets/split_scope_selector.dart';

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

  /// Get the trip's currency code
  String get _tripCurrency {
    final trips = ref.read(userTripsProvider).valueOrNull;
    debugPrint('[EXPENSE] _tripCurrency: tripId=${widget.tripId}, '
        'userTrips=${trips?.length ?? 0}');
    if (trips == null) return 'OMR';
    final trip = trips.cast<Trip?>().firstWhere(
      (t) => t!.id == widget.tripId,
      orElse: () => null,
    );
    debugPrint('[EXPENSE] _tripCurrency: found=${trip != null}, '
        'currency=${trip?.currency ?? "OMR (default)"}');
    return trip?.currency ?? 'OMR';
  }

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
          // Limit decimal places based on trip currency
          final maxDecimals = AppFormatters.currencyConfig[_tripCurrency]?.decimals ?? 3;
          if (_amount.contains('.')) {
            final parts = _amount.split('.');
            if (parts[1].length < maxDecimals) {
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
    Decimal amount;
    try {
      amount = Decimal.parse(_amount);
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid amount')),
        );
      }
      return;
    }
    if (amount <= Decimal.zero) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Amount must be greater than zero')),
        );
      }
      return;
    }
    final note = _noteController.text.trim();

    debugPrint('[EXPENSE] _submit: tripId=${widget.tripId}');
    debugPrint('[EXPENSE] _submit: looking up currentParticipant...');

    final currentParticipant = ref.read(
      currentParticipantProvider(widget.tripId),
    );
    debugPrint('[EXPENSE] _submit: currentParticipant=${currentParticipant?.id ?? "NULL"}');
    if (currentParticipant == null) {
      // Log additional context to diagnose
      final trips = ref.read(userTripsProvider).valueOrNull;
      debugPrint('[EXPENSE] _submit: userTrips count=${trips?.length ?? 0}');
      if (trips != null) {
        for (final t in trips) {
          debugPrint('[EXPENSE]   trip: id=${t.id}, name=${t.name}, leaderId=${t.leaderId}');
        }
      }
      final participantsAsync = ref.read(tripLogisticsParticipantsProvider(widget.tripId));
      debugPrint('[EXPENSE] _submit: participantsAsync state=${participantsAsync.runtimeType}');
      participantsAsync.whenData((participants) {
        debugPrint('[EXPENSE]   participants: ${participants.length}');
        for (final p in participants) {
          debugPrint('[EXPENSE]     id=${p.id}, userId=${p.userId}, name=${p.displayName}');
        }
      });
      final user = ref.read(currentUserProvider);
      debugPrint('[EXPENSE] _submit: currentUser supabaseId=${user?.id}');

      ref.read(expenseErrorProvider.notifier).state =
          'Could not identify your participant record.';
      return;
    }

    // Upload receipt if one was selected
    String? receiptUrl;
    if (_receiptPath != null) {
      setState(() => _isUploadingReceipt = true);
      receiptUrl = await _uploadReceipt(_receiptPath!);
      if (!mounted) return;
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
      builder: (context) => ExpenseSuccessDialog(
        expense: expense,
        currency: _tripCurrency,
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

    categoriesAsync.when(
      data: (cats) => debugPrint('[EXPENSE] build: ${cats.length} categories for tripId=${widget.tripId}'),
      loading: () => debugPrint('[EXPENSE] build: categories LOADING for tripId=${widget.tripId}'),
      error: (e, _) => debugPrint('[EXPENSE] build: categories ERROR for tripId=${widget.tripId}: $e'),
    );

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
                  SingleChildScrollView(
                    child: AmountInputSection(
                      amount: _amount,
                      currency: _tripCurrency,
                      onKeyPress: _onKeyPress,
                    ),
                  ),
                  CategorySelectionStep(
                    categoriesAsync: categoriesAsync,
                    selectedCategoryId: _selectedCategoryId,
                    onCategorySelected: (id) {
                      setState(() => _selectedCategoryId = id);
                    },
                  ),
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
          SplitScopeSelector(
            tripId: widget.tripId,
            scope: _scope,
            onScopeChanged: (scope) => setState(() => _scope = scope),
            customSplitParticipants: _customSplitParticipants,
            onCustomSplitChanged: (participants) {
              setState(() {
                _customSplitParticipants.clear();
                _customSplitParticipants.addAll(participants);
              });
            },
            selectedSubGroupId: _selectedSubGroupId,
            onAutoSelectSubGroup: _autoSelectUserSubGroup,
            onSubGroupIdCleared: (value) {
              setState(() => _selectedSubGroupId = value);
            },
            selectedPayerId: _selectedPayerId,
            onPayerChanged: (value) {
              setState(() => _selectedPayerId = value);
            },
          ),
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
          ReceiptPickerSection(
            receiptPath: _receiptPath,
            isUploading: _isUploadingReceipt,
            onPick: _pickReceipt,
            onRemove: () => setState(() => _receiptPath = null),
          ),
          if (error != null) _buildErrorBanner(error),
        ],
      ),
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
