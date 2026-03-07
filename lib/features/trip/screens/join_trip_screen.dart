import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../models/trip_model.dart';
import '../providers/trip_provider.dart';

/// Join Trip Screen — two-step flow: enter code, then pick your name
class JoinTripScreen extends ConsumerStatefulWidget {
  const JoinTripScreen({super.key});

  @override
  ConsumerState<JoinTripScreen> createState() => _JoinTripScreenState();
}

class _JoinTripScreenState extends ConsumerState<JoinTripScreen> {
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Step 2 state
  Trip? _foundTrip;
  List<Participant>? _unclaimedNames;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _findTrip() async {
    if (!_formKey.currentState!.validate()) return;

    final code = _codeController.text.trim().toUpperCase();
    final tripService = ref.read(tripServiceProvider);
    final result = await tripService.findTripForJoin(code);

    if (result == null) {
      // Either error (shown via tripErrorProvider) or already a member
      final error = ref.read(tripErrorProvider);
      if (error == null && mounted) {
        // Already a member — navigate home
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You\'re already in this trip!'),
            backgroundColor: AppColors.primary,
          ),
        );
        context.go('/home');
      }
      return;
    }

    setState(() {
      _foundTrip = result.trip;
      _unclaimedNames = result.unclaimed;
    });
  }

  Future<void> _claimName(Participant participant) async {
    final tripService = ref.read(tripServiceProvider);
    final trip = await tripService.claimParticipant(
      _foundTrip!.id,
      participant.id,
    );

    if (trip != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Iconsax.tick_circle, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Text('Joined "${trip.name}" as ${participant.displayName}!'),
            ],
          ),
          backgroundColor: AppColors.primary,
        ),
      );
      context.go('/home');
    }
  }

  void _goBack() {
    if (_foundTrip != null) {
      // Go back to code entry
      setState(() {
        _foundTrip = null;
        _unclaimedNames = null;
      });
      ref.read(tripErrorProvider.notifier).state = null;
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(tripLoadingProvider);
    final error = ref.watch(tripErrorProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: _foundTrip != null
                  ? _buildNamePicker(isLoading, error)
                  : _buildCodeEntry(isLoading, error),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Iconsax.arrow_left),
            onPressed: _goBack,
          ),
          Expanded(
            child: Text(
              _foundTrip != null ? 'Pick Your Name' : 'Join Trip',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildCodeEntry(bool isLoading, String? error) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Header
            _buildCodeHeader().animate().fadeIn().slideY(begin: 0.1),

            const SizedBox(height: 48),

            // Code Input Card
            _buildCodeCard(error)
                .animate()
                .fadeIn(delay: 200.ms)
                .slideY(begin: 0.1),

            const SizedBox(height: 32),

            // Find Trip Button
            _buildFindButton(isLoading)
                .animate()
                .fadeIn(delay: 300.ms),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeHeader() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Iconsax.login, size: 36, color: Colors.white),
        ),
        const SizedBox(height: 16),
        Text(
          'Join the Adventure',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the 6-character invite code',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildCodeCard(String? error) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          TextFormField(
            controller: _codeController,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
              color: AppColors.textPrimary,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              UpperCaseTextFormatter(),
            ],
            decoration: InputDecoration(
              hintText: '------',
              hintStyle: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                color: AppColors.border,
              ),
              counterText: '',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter the invite code';
              }
              if (value.length != 6) {
                return 'Code must be 6 characters';
              }
              return null;
            },
            onFieldSubmitted: (_) => _findTrip(),
          ),
          const SizedBox(height: 8),
          Text(
            'Ask your trip organizer for the code',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Iconsax.warning_2, color: AppColors.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error,
                      style: const TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFindButton(bool isLoading) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: isLoading ? null : _findTrip,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
          ),
          child: isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Iconsax.search_normal),
                    SizedBox(width: 8),
                    Text('Find Trip'),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildNamePicker(bool isLoading, String? error) {
    final unclaimed = _unclaimedNames ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Trip info header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppColors.cardShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Iconsax.airplane, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _foundTrip!.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${unclaimed.length} name${unclaimed.length == 1 ? '' : 's'} available',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn().slideY(begin: 0.1),

          const SizedBox(height: 24),

          // Prompt
          Text(
            'Which one is you?',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ).animate().fadeIn(delay: 100.ms),

          const SizedBox(height: 16),

          if (unclaimed.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(
                children: [
                  Icon(Iconsax.warning_2, size: 48, color: AppColors.textMuted),
                  SizedBox(height: 16),
                  Text(
                    'All names have been claimed',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Ask the trip creator to add your name',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 200.ms)
          else
            ...List.generate(unclaimed.length, (index) {
              final participant = unclaimed[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: isLoading ? null : () => _claimName(participant),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.borderLight, width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Center(
                              child: Text(
                                (participant.displayName ?? '?')[0].toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              participant.displayName ?? 'Unknown',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const Icon(
                            Iconsax.arrow_right_3,
                            size: 18,
                            color: AppColors.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: Duration(milliseconds: 200 + (index * 80))).slideY(begin: 0.1);
            }),

          // Error display
          if (error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Iconsax.warning_2, color: AppColors.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error,
                      style: const TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Uppercase text formatter
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
